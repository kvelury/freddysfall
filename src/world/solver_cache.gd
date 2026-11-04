class_name SolverCache
extends RefCounted

## What the solver works out about a room that depends on nothing but the room
## and the solver itself, kept on disk between runs of tools/validate.sh. Most
## of a run is this work (every ledge's jumps), so a run after editing one room only
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
## 3: a room's jumps are kept per Abilities.movement_key, so a jump worked out
## with one set of movement stats is never reused for another.
const FORMAT := 3

## Everything a jump's result depends on.
const SOLVER_FILES: Array[String] = [
	"res://src/world/reach_graph.gd",
	"res://src/world/solver/move_provider.gd",
	"res://src/world/solver/ground_moves.gd",
	"res://src/world/solver/air_moves.gd",
	"res://src/world/solver/lash_moves.gd",
	"res://src/tongue/tongue_reach.gd",
	"res://src/imprint/imprint_rules.gd",
	"res://src/player/movement_sim.gd",
	"res://src/player/jump_plan.gd",
	"res://src/player/movement_config.gd",
	"res://src/player/movement.tres",
	"res://src/world/door.gd",
	"res://src/world/tiles.gd",
	"res://src/world/room_info.gd",
	"res://src/world/entities.gd",
	"res://src/world/kinds/entity_kind.gd",
	"res://src/world/kinds/pickup_kind.gd",
	"res://src/world/kinds/token_kind.gd",
	"res://src/world/kinds/health_kind.gd",
	"res://src/world/kinds/machine_kind.gd",
	"res://src/world/kinds/save_kind.gd",
	"res://src/world/kinds/platform_kind.gd",
	"res://src/world/kinds/emitter_kind.gd",
	"res://src/world/kinds/spinner_kind.gd",
	"res://src/world/kinds/breakable_kind.gd",
	"res://src/world/mover.gd",
	"res://src/world/platform_path.gd",
	"res://src/world/emitter_path.gd",
	"res://src/world/spinner_path.gd",
	"res://src/world/movers.gd",
	"res://src/world/entities/token_machine.gd",
	"res://src/world/entities/save_machine.gd",
	"res://src/world/entities/pickup.gd",
	"res://src/core/grid.gd",
	"res://src/core/display.gd",
	"res://src/world/solver_cache.gd",
]

## Reached from the solver, but a change to it cannot change a cached jump.
## The test that checks the fingerprint's closure (cache_test) allows these and
## fails on anything else it reaches that is not in SOLVER_FILES. A stat that
## changes how a body moves belongs in Abilities.movement_key, not in this list.
const FINGERPRINT_EXEMPT := {
	"res://src/core/abilities.gd": "which jumps get used depends on the abilities, not how one jump moves; a stat that changes the movement goes in Abilities.movement_key",
	"res://src/core/upgrades.gd": "names which stat a pickup raises; the jumps themselves do not read it",
	"res://src/core/upgrade_def.gd": "the fields of an upgrade; the jumps themselves do not read it",
	"res://src/core/progression.gd": "the saved snapshot; a jump does not read it",
	"res://src/core/controls.gd": "the controls page; upgrades.gd only checks that a row id exists",
	"res://src/core/palette.gd": "colours for drawing, which a jump never reads",
	"res://src/core/pixel_art.gd": "drawing pictures, which a jump never reads",
	"res://src/core/pixel_shapes.gd": "drawing pictures, which a jump never reads",
	"res://src/player/freddy_sprites.gd": "the player's pictures",
	"res://src/player/inventory_marks.gd": "marks drawn on the player",
	"res://src/player/player.gd": "the running player; the solver calls MovementSim, not this node",
	"res://src/player/player_animator.gd": "which picture the player shows",
	"res://src/player/player_body.gd": "drawing the player",
	"res://src/tongue/tongue_lash.gd": "the running tongue; the solver's lash and this one share TongueReach, which is in the fingerprint",
	"res://src/tongue/tongue_motion.gd": "the running tongue's curves, which the solver's lash does not use",
	"res://src/world/entities/breakable_wall.gd": "the wall's node; the solver reads its cells from RoomInfo",
	"res://src/world/entities/emitter_view.gd": "drawing an emitter; the solver reads EmitterPath",
	"res://src/world/entities/health_pip.gd": "the pip's node; the solver uses Pickup's touch size",
	"res://src/world/entities/moving_platform.gd": "drawing a platform; the solver reads PlatformPath",
	"res://src/world/entities/spinner_view.gd": "drawing a spinner; the solver reads SpinnerPath",
	"res://src/world/entities/token.gd": "the token's node; the solver uses Pickup's touch size",
	"res://src/world/exit_halo.gd": "the glow in a doorway",
	"res://src/world/exit_rules.gd": "decides when a room opens during the search, after the jumps are worked out",
	"res://src/world/entity_def.gd": "a thing's id and props, hashed in the room fingerprint",
	"res://src/world/room.gd": "the running room; the solver reads RoomInfo",
	"res://src/world/room_parser.gd": "its output is the RoomInfo the room fingerprint hashes",
	"res://src/world/shatter.gd": "the burst of shards when something breaks",
}

## The directory the files are in.
var directory := ""
## The solver's fingerprint. Public so a test can change it.
var solver := ""
## How much came from the cache and how much was worked out, for the report.
var stats := {"edge_rooms_cached": 0, "edge_rooms_solved": 0, "air_rooms_cached": 0, "air_rooms_solved": 0}
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
			if edges is Dictionary:
				entry.edges = edges
			var air_edges = data.get("air_edges")
			if air_edges is Dictionary:
				entry.air_edges = air_edges
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
		var data := {"format": FORMAT, "solver": solver, "room": entry.fingerprint, "edges": entry.edges, "air_edges": entry.air_edges}
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
	## movement_key -> (ledge index as text -> what it reaches).
	var edges := {}
	## The same for what needs an air jump, worked out only when a solve has one.
	var air_edges := {}
	var dirty := false

	func store_edges(key: String, ledges: Array) -> void:
		edges[key] = _pack_ledges(ledges, false)
		dirty = true

	func store_air_edges(key: String, ledges: Array) -> void:
		air_edges[key] = _pack_ledges(ledges, true)
		dirty = true

	func _pack_ledges(ledges: Array, air: bool) -> Dictionary:
		var packed := {}
		for ledge: ReachGraph.Ledge in ledges:
			packed[str(ledge.index)] = SolverCache.pack(ledge, air)
		return packed

