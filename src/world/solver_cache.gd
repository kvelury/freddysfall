class_name SolverCache
extends RefCounted

## What the solver works out about a room that depends on nothing but the room
## and the solver itself, kept on disk between runs of tools/validate.sh. Most
## of a run is this work (every ledge's jumps, and the jumps from every
## platform Imprint could put down), so a run after editing one room only
## redoes that room.
##
## A room's file is used only if both fingerprints match what was saved:
## - the room's, a hash of everything the room is (its grid with the openings
##   that lead nowhere sealed, its doors and where they lead, its things,
##   where it sits), so a neighbour that appears or moves changes it;
## - the solver's, a hash of the code and the movement numbers that decide what
##   a jump does. Change any of them and every room is worked out again.
## Anything that cannot be read is ignored, so the cache can never fail a run.
## The tests do not use it: they leave `ReachGraph.cache` empty.

## Goes up when the shape of the files changes.
const FORMAT := 2

## Everything a jump's result depends on.
const SOLVER_FILES: Array[String] = [
	"res://src/world/reach_graph.gd",
	"res://src/world/imprint_search.gd",
	"res://src/imprint/imprint_rules.gd",
	"res://src/player/movement_sim.gd",
	"res://src/player/movement_config.gd",
	"res://src/player/movement.tres",
	"res://src/world/door.gd",
	"res://src/world/tiles.gd",
	"res://src/world/room_info.gd",
	"res://src/world/entities.gd",
	"res://src/world/platform_path.gd",
	"res://src/world/movers.gd",
	"res://src/world/entities/token_machine.gd",
	"res://src/world/entities/save_machine.gd",
	"res://src/world/entities/pickup.gd",
	"res://src/core/grid.gd",
]

## The directory the files are in.
var directory := ""
## The solver's fingerprint. Public so a test can change it.
var solver := ""
## How much came from the cache and how much was worked out, for the report.
var stats := {"edge_rooms_cached": 0, "edge_rooms_solved": 0, "legs_cached": 0, "legs_solved": 0, "air_rooms_cached": 0, "air_rooms_solved": 0}
var _rooms := {}


func _init(cache_directory: String) -> void:
	directory = cache_directory
	solver = solver_fingerprint()


## A hash of every file the solver's answers depend on, and the file format.
static func solver_fingerprint() -> String:
	var text := "format %d\n" % FORMAT
	for path in SOLVER_FILES:
		if FileAccess.file_exists(path):
			text += "%s\n%s\n" % [path, FileAccess.get_file_as_string(path)]
	return text.sha256_text()


## A hash of what makes a room what it is to the solver.
static func room_fingerprint(info: RoomInfo) -> String:
	var text := "%s|%s|%s|%s|%s|%s|%s|%s\n" % [info.id, info.grid_pos, info.screens, info.cell_size, info.spawn_cell, info.has_spawn, info.exit_rule, info.traps_allowed]
	text += "\n".join(info.rows) + "\n"
	for door in info.exits:
		text += "door %s %s %s %s %s\n" % [door.edge, door.rect, door.screen, door.dest_id, door.dest_rect]
	for cell in info.no_imprint:
		text += "no_imprint %s\n" % cell
	for wall_id in info.broken:
		text += "broken %s\n" % wall_id
	for def in info.entities:
		var keys: Array = def.props.keys()
		keys.sort()
		var props := []
		for key in keys:
			props.append("%s=%s" % [key, def.props[key]])
		text += "thing %s %s %s %s\n" % [def.type, def.id, def.cell, ",".join(props)]
	return text.sha256_text()


## The kept answers for `info`, loaded from its file if they are still good.
func entry_for(info: RoomInfo) -> Entry:
	if _rooms.has(info.id):
		return _rooms[info.id]
	var entry := Entry.new()
	entry.room_id = info.id
	entry.fingerprint = room_fingerprint(info)
	var path := _path(info.id)
	if FileAccess.file_exists(path):
		var parser := JSON.new()
		var data = parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null
		if data is Dictionary and int(data.get("format", -1)) == FORMAT and data.get("solver") == solver and data.get("room") == entry.fingerprint:
			var edges = data.get("edges")
			var legs = data.get("legs")
			if edges is Dictionary:
				entry.edges = edges
				entry.has_edges = true
			if legs is Dictionary:
				entry.legs = legs
			var air_edges = data.get("air_edges")
			if air_edges is Dictionary:
				entry.air_edges = air_edges
				entry.has_air = true
	_rooms[info.id] = entry
	return entry


## Writes every room that has something new. Returns how many files it wrote.
func save() -> int:
	var written := 0
	for id in _rooms:
		var entry: Entry = _rooms[id]
		if not entry.dirty:
			continue
		if not DirAccess.dir_exists_absolute(_absolute(directory)):
			DirAccess.make_dir_recursive_absolute(_absolute(directory))
			# The editor should not go through a folder of data files.
			var marker := FileAccess.open(directory.path_join(".gdignore"), FileAccess.WRITE)
			if marker != null:
				marker.close()
		var file := FileAccess.open(_path(id), FileAccess.WRITE)
		if file == null:
			continue
		var data := {"format": FORMAT, "solver": solver, "room": entry.fingerprint, "edges": entry.edges, "legs": entry.legs, "air_edges": entry.air_edges}
		file.store_string(JSON.stringify(data, "", true, true))
		entry.dirty = false
		written += 1
	return written


func _path(room_id: String) -> String:
	return directory.path_join("%s.json" % room_id)


static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


## Fills `ledge` with what `data` (from `pack`) says it can reach.
static func unpack(ledge: ReachGraph.Ledge, data: Dictionary, air := false) -> void:
	for index in data.get("to", []):
		ledge.add_ledge(int(index), air)
	for touch in data.get("touches", []):
		ledge.add_touch(int(touch[0]), Vector2(float(touch[1]), float(touch[2])), Vector2(float(touch[3]), float(touch[4])), air)
	for index in data.get("pickups", []):
		ledge.add_pickup(int(index), air)


## What `ledge` can reach, as plain data: the ledges it jumps to, the door
## touches, and the pickups.
static func pack(ledge: ReachGraph.Ledge, air := false) -> Dictionary:
	var touches := []
	for touch in (ledge.air_touches if air else ledge.touches):
		touches.append([touch.door, touch.position.x, touch.position.y, touch.velocity.x, touch.velocity.y])
	return {"to": (ledge.air_to_ledges if air else ledge.to_ledges).duplicate(), "touches": touches, "pickups": (ledge.air_pickups if air else ledge.pickups).duplicate()}


## One room's kept answers.
class Entry extends RefCounted:
	var room_id := ""
	var fingerprint := ""
	## Ledge index (as text) -> what it reaches, once the room's ledges are done.
	var edges := {}
	var has_edges := false
	## The same for what needs an air jump, worked out only when a solve has one.
	var air_edges := {}
	var has_air := false
	## "x|y|width|limit" of a platform -> what a body standing on it reaches.
	var legs := {}
	var dirty := false

	func store_edges(ledges: Array) -> void:
		edges = {}
		for ledge: ReachGraph.Ledge in ledges:
			edges[str(ledge.index)] = SolverCache.pack(ledge)
		has_edges = true
		dirty = true

	func store_air_edges(ledges: Array) -> void:
		air_edges = {}
		for ledge: ReachGraph.Ledge in ledges:
			air_edges[str(ledge.index)] = SolverCache.pack(ledge, true)
		has_air = true
		dirty = true

	func store_leg(key: String, ledge: ReachGraph.Ledge) -> void:
		legs[key] = SolverCache.pack(ledge)
		dirty = true
