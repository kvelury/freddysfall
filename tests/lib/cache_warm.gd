class_name CacheWarm
extends RefCounted

## Fills the solver cache in pieces for tools/validate.sh --jobs, so a big room
## is spread over several processes. See tests/validate.gd for the flags.
##
## It warms what a solve reads, with the abilities a solve has when it reads it:
## - a room's jumps for the room and every set of its walls broken: without an
##   air jump, and with one (the jumps, kept under Abilities.movement_key, and
##   the air jumps);
## - its Tongue Climb hangs with the Tongue Climb upgrade applied as a pickup
##   applies it (Abilities.apply, so its `also` stats come with it: the longer
##   tongue), without and with an air jump. ClimbMoves keys what it keeps by those
##   abilities (`_signature`), so a hang worked out with any other set is never
##   read by a solve.
##
## This lives with the tools, not the solver: it is not in
## SolverCache.SOLVER_FILES, so changing it never makes the committed cache stale.
## A missing piece is not an error: a solve works out whatever the cache lacks.

## The upgrade whose abilities the climb pieces are worked out with.
const CLIMB_UPGRADE := "tongue_climb"
const PARTS := ["jumps0", "jumps1", "climb0", "climb1"]

var _graph: ReachGraph
var _rooms: Dictionary


func _init(graph: ReachGraph, rooms: Dictionary) -> void:
	_graph = graph
	_rooms = rooms


## The pieces the cache lacks, slowest first by build/room-times.json; a room
## with no time yet (a new one) goes first.
func plan() -> Array[String]:
	var times := {}
	var file := FileAccess.open("res://build/room-times.json", FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			times = parsed
	var rows: Array = []
	var ids: Array = _rooms.keys()
	ids.sort()
	for id: String in ids:
		var cost := float(times.get(id, INF))
		var jumps := [false, false]
		for info in _states(id):
			var entry := _graph.cache.entry_for(info)
			for air in 2:
				var key := _move_key(air)
				if not entry.edges.has(key) or (air == 1 and not entry.air_edges.has(key)):
					jumps[air] = true
				if not entry.climb.has(_climb_signature(air)):
					rows.append([cost, "%s:climb%d" % [info.id, air]])
		for air in 2:
			if jumps[air]:
				rows.append([cost, "%s:jumps%d" % [id, air]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and String(a[1]) < String(b[1])))
	var out: Array[String] = []
	for row in rows:
		out.append(String(row[1]))
	return out


## Works out one piece into the graph's cache. 0, or 1 for a piece that names
## no room or part.
func work(piece: String) -> int:
	var parts := piece.split(":")
	if parts.size() != 2 or not PARTS.has(parts[1]):
		print("FAIL no such piece %s (want <room>:%s)" % [piece, "|".join(PARTS)])
		return 1
	var names := parts[0].split("~")
	if not _rooms.has(names[0]):
		print("FAIL no room %s" % names[0])
		return 1
	if parts[1].begins_with("jumps"):
		var air := int(parts[1].right(1))
		var jumps := _graph.abilities.air_jumps
		_graph.abilities.air_jumps = air
		for info in _states(names[0]):
			_graph._ensure_edges(info)
			if air > 0:
				_graph._ensure_air_edges(info)
		_graph.abilities.air_jumps = jumps
		return 0
	var walls: Array[String] = []
	for i in range(1, names.size()):
		walls.append(names[i])
	var info: RoomInfo = _rooms[names[0]] if walls.is_empty() else _graph._variant_for(names[0], walls)
	if info == null:
		print("FAIL no copy %s" % parts[0])
		return 1
	# The ledges' jumps come from the cache (the jumps0 piece went first).
	_graph._ensure_edges(info)
	var kept := _with_climb(int(parts[1].right(1)))
	for provider in _graph._providers:
		if provider is ClimbMoves:
			(provider as ClimbMoves).warm(info)
	_restore(kept)
	return 0


## Joins every piece's folder under `pieces` into `target`. A file is written
## only if it gains something. 0, or 1 if nothing could be read.
func merge(pieces: String, target: String) -> int:
	var root := ProjectSettings.globalize_path(pieces)
	var dirs := DirAccess.get_directories_at(root)
	if dirs.is_empty():
		print("FAIL no piece folders in %s" % root)
		return 1
	var solver := SolverCache.solver_fingerprint()
	var joined := {}
	for dir in dirs:
		for name in DirAccess.get_files_at(root.path_join(dir)):
			if not name.ends_with(".json"):
				continue
			var data := _read(root.path_join(dir).path_join(name), solver)
			if data.is_empty():
				continue
			if not joined.has(name):
				joined[name] = data
			elif joined[name]["room"] != data["room"]:
				print("warn %s in %s is for another version of the room; left out" % [name, dir])
			else:
				_join(joined[name], data)
	var out := ProjectSettings.globalize_path(target)
	var written := 0
	for name: String in joined:
		var path := out.path_join(name)
		var old := _read(path, solver)
		var data: Dictionary = joined[name]
		if not old.is_empty() and old["room"] == data["room"]:
			_join(data, old)
			if data == old:
				continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("FAIL could not write %s" % path)
			return 1
		file.store_string(JSON.stringify(data, "", true, true))
		file.close()
		written += 1
	print("merge: %d pieces, %d files written" % [dirs.size(), written])
	return 0


## The room and each set of its walls broken, as ReachGraph.warm goes through them.
func _states(id: String) -> Array[RoomInfo]:
	var info: RoomInfo = _rooms[id]
	var out: Array[RoomInfo] = [info]
	var walls: Array[String] = []
	for wall_id in info.breakables:
		walls.append(String(wall_id))
	walls.sort()
	var subsets: Array = [[]]
	for wall_id in walls:
		var grown: Array = []
		for existing in subsets:
			var next: Array = (existing as Array).duplicate()
			next.append(wall_id)
			grown.append(next)
		for extra in grown:
			subsets.append(extra)
			if subsets.size() >= ReachGraph.MAX_WALL_STATES:
				break
		if subsets.size() >= ReachGraph.MAX_WALL_STATES:
			break
	for broken in subsets:
		if (broken as Array).is_empty():
			continue
		var names: Array[String] = []
		names.assign(broken)
		var variant := _graph._variant_for(id, names)
		if variant == null:
			break
		out.append(variant)
	return out


## Abilities.movement_key with `air` air jumps.
func _move_key(air: int) -> String:
	var jumps := _graph.abilities.air_jumps
	_graph.abilities.air_jumps = air
	var key := _graph.abilities.movement_key()
	_graph.abilities.air_jumps = jumps
	return key


func _climb_signature(air: int) -> String:
	var kept := _with_climb(air)
	var signature := ""
	for provider in _graph._providers:
		if provider is ClimbMoves:
			signature = (provider as ClimbMoves)._signature()
	_restore(kept)
	return signature


## Gives the graph's abilities Tongue Lash, the climb upgrade (with its `also`)
## and `air` air jumps. Returns what to put back.
func _with_climb(air: int) -> Dictionary:
	var abilities := _graph.abilities
	var kept := {}
	for stat in Abilities.stats():
		kept[stat] = abilities.get(stat)
	abilities.tongue_unlocked = true
	abilities.apply(Upgrades.get_def(CLIMB_UPGRADE), true)
	abilities.air_jumps = air
	return kept


func _restore(kept: Dictionary) -> void:
	for stat in kept:
		_graph.abilities.set(stat, kept[stat])


## The file's contents if it was written with this solver and format, else {}.
func _read(path: String, solver: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("format", -1)) != SolverCache.FORMAT or data.get("solver") != solver:
		return {}
	return data


## Adds to `into` whatever `from` has that it lacks, two levels down in each part
## (what a part is keyed by, then each ledge or hang): pieces work out the same
## thing the same way, so where both have it they agree.
func _join(into: Dictionary, from: Dictionary) -> void:
	for part in ["edges", "air_edges", "climb"]:
		var mine: Dictionary = into.get(part, {})
		var theirs: Variant = from.get(part, {})
		if not theirs is Dictionary:
			continue
		for key in theirs:
			if not mine.has(key):
				mine[key] = theirs[key]
			elif mine[key] is Dictionary and theirs[key] is Dictionary:
				for inner in theirs[key]:
					if not (mine[key] as Dictionary).has(inner):
						mine[key][inner] = theirs[key][inner]
		into[part] = mine
