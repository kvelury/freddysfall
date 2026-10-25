extends SceneTree

## The solver's cache on disk: a run that reads it gets exactly the answers of a
## run that does not, and a room is only taken from it while nothing the room
## depends on has changed. Uses a folder of its own, never the real cache.

const DIR := "user://cache_test"

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	_clear()
	var ok := _files()
	ok = _same_answers() and ok
	ok = _what_invalidates() and ok
	ok = _damaged() and ok
	ok = _upgrade() and ok
	_clear()
	print("CACHE %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## The files the solver's fingerprint covers all exist, and the ones that
## decide a jump are among them. A typo here would drop one without a sound.
func _files() -> bool:
	var ok := true
	var missing := []
	for path in SolverCache.SOLVER_FILES:
		if not FileAccess.file_exists(path):
			missing.append(path)
	ok = _check(missing.is_empty(), "every file the solver's fingerprint covers exists %s" % [missing]) and ok
	for name in ["reach_graph.gd", "imprint_search.gd", "movement_sim.gd", "movement.tres", "movement_config.gd", "door.gd", "imprint_rules.gd", "room_info.gd", "grid.gd"]:
		var listed := false
		for path in SolverCache.SOLVER_FILES:
			listed = listed or path.ends_with("/" + name)
		ok = _check(listed, "the fingerprint covers %s" % name) and ok
	ok = _check(SolverCache.solver_fingerprint() == SolverCache.solver_fingerprint() and SolverCache.solver_fingerprint().length() == 64, "and it is a stable hash") and ok
	return ok


## A run with the cache, cold and then warm, says what a run without it says.
func _same_answers() -> bool:
	var ok := true
	var rooms := _world()
	var plain := _run(rooms, null, 2)
	var cold_cache := SolverCache.new(DIR)
	var cold := _run(rooms, cold_cache, 2)
	ok = _check(_same(plain, cold), "a cold run with the cache says what a run without it says") and ok
	ok = _check(cold_cache.stats["edge_rooms_cached"] == 0 and cold_cache.stats["edge_rooms_solved"] == 2 and cold_cache.stats["legs_cached"] == 0 and cold_cache.stats["legs_solved"] > 0, "and it worked everything out (%s)" % [cold_cache.stats]) and ok
	var written := cold_cache.save()
	ok = _check(written == 2 and FileAccess.file_exists(DIR + "/1.json") and FileAccess.file_exists(DIR + "/2.json"), "one file is written per room (%d)" % written) and ok
	ok = _check(cold_cache.save() == 0, "and nothing is written twice") and ok

	var warm_cache := SolverCache.new(DIR)
	var warm := _run(rooms, warm_cache, 2)
	ok = _check(_same(plain, warm), "a warm run says it too (%d reached, %d errors)" % [warm.reached_ledges, warm.errors.size()]) and ok
	ok = _check(warm_cache.stats["edge_rooms_cached"] == 2 and warm_cache.stats["edge_rooms_solved"] == 0 and warm_cache.stats["legs_solved"] == 0 and warm_cache.stats["legs_cached"] == cold_cache.stats["legs_solved"], "and it took every room and every leg from the cache (%s)" % [warm_cache.stats]) and ok
	ok = _check(warm_cache.save() == 0, "and has nothing to write") and ok
	return ok


## A room is worked out again when it changes, or when a neighbour changes what
## its doors lead to, or when the solver does. A room that did not is not.
func _what_invalidates() -> bool:
	var ok := true
	var rooms := _world()
	var cache := SolverCache.new(DIR)
	_run(rooms, cache, 2)
	cache.save()

	# Edit room 2 only.
	var edited := _world({Vector2i(10, 12): "#", Vector2i(11, 12): "#"})
	var after_edit := SolverCache.new(DIR)
	var edited_report := _run(edited, after_edit, 2)
	ok = _check(after_edit.stats["edge_rooms_cached"] == 1 and after_edit.stats["edge_rooms_solved"] == 1, "editing room 2 redoes room 2 and not room 1 (%s)" % [after_edit.stats]) and ok
	ok = _check(_same(_run(edited, null, 2), edited_report), "and the answers are the ones of a run without the cache") and ok
	after_edit.save()

	# Room 1's door leads nowhere once room 2 is gone, so it is sealed: a different room.
	var alone := _world({}, false)
	var after_remove := SolverCache.new(DIR)
	_run(alone, after_remove, 2)
	ok = _check(after_remove.stats["edge_rooms_solved"] == 1 and after_remove.stats["edge_rooms_cached"] == 0, "removing the neighbour changes room 1's doors, so room 1 is redone (%s)" % [after_remove.stats]) and ok

	# The solver changed: everything is redone.
	cache = SolverCache.new(DIR)
	cache.solver = "another solver"
	_run(edited, cache, 2)
	ok = _check(cache.stats["edge_rooms_cached"] == 0 and cache.stats["legs_cached"] == 0 and cache.stats["edge_rooms_solved"] == 2, "a different solver fingerprint redoes every room (%s)" % [cache.stats]) and ok

	# A room's fingerprint covers what is in it.
	var a: RoomInfo = rooms["1"]
	var b: RoomInfo = _world({}, true, "", {Vector2i(5, 5): "^"})["1"]
	var c: RoomInfo = _world({}, true, "legend:\n  U = pickup id=key upgrade=imprint\n---\n", {Vector2i(4, 16): "U"})["1"]
	ok = _check(SolverCache.room_fingerprint(a) == SolverCache.room_fingerprint(_world()["1"]), "the same room has the same fingerprint") and ok
	ok = _check(SolverCache.room_fingerprint(a) != SolverCache.room_fingerprint(b), "a hazard changes it") and ok
	ok = _check(SolverCache.room_fingerprint(a) != SolverCache.room_fingerprint(c), "a pickup changes it") and ok
	var d: RoomInfo = _world({}, true, "legend:\n  U = pickup id=key upgrade=imprint_width value=3\n---\n", {Vector2i(4, 16): "U"})["1"]
	ok = _check(SolverCache.room_fingerprint(c) != SolverCache.room_fingerprint(d), "and so does what it gives, with the room's cells the same") and ok
	return ok


## A file that cannot be read is ignored, and is replaced by a good one.
func _damaged() -> bool:
	var ok := true
	var rooms := _world()
	var plain := _run(rooms, null, 2)
	for text in ["not json at all", "[1, 2, 3]", "{\"format\": 1}", "{\"format\": 99, \"solver\": \"x\", \"room\": \"y\", \"edges\": 5}"]:
		_clear()
		var seed_cache := SolverCache.new(DIR)
		_run(rooms, seed_cache, 2)
		seed_cache.save()
		var file := FileAccess.open(DIR + "/1.json", FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var cache := SolverCache.new(DIR)
		var report := _run(rooms, cache, 2)
		ok = _check(_same(plain, report) and cache.stats["edge_rooms_solved"] == 1 and cache.stats["edge_rooms_cached"] == 1, "a damaged file (%s) is ignored and room 1 is redone (%s)" % [text.left(18), cache.stats]) and ok
		ok = _check(cache.save() >= 1, "and it is written again") and ok
	var healed := SolverCache.new(DIR)
	_run(rooms, healed, 2)
	ok = _check(healed.stats["edge_rooms_solved"] == 0, "after which it is read") and ok
	return ok


## Another width is another set of platforms: the cache has none of its legs, and
## still gives the right answers.
func _upgrade() -> bool:
	var ok := true
	_clear()
	var rooms := _world()
	var cache := SolverCache.new(DIR)
	_run(rooms, cache, 2)
	cache.save()
	var wide_plain := _run(rooms, null, 3)
	var wide_cache := SolverCache.new(DIR)
	var wide := _run(rooms, wide_cache, 3)
	ok = _check(_same(wide_plain, wide), "a wider platform, from a cache of narrow ones, says what a run without the cache says") and ok
	ok = _check(wide_cache.stats["edge_rooms_cached"] == 2 and wide_cache.stats["legs_solved"] > 0, "the rooms' jumps are reused and the new legs are worked out (%s)" % [wide_cache.stats]) and ok
	wide_cache.save()
	var widths := {}
	var saved = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/1.json"))
	for key in saved["legs"]:
		widths[String(key).get_slice("|", 2)] = true
	ok = _check(not widths.is_empty() and widths.keys() == ["1"], "every stored leg is one block wide (%s)" % [widths.keys()]) and ok
	return ok


# --- helpers ---------------------------------------------------------------


func _run(rooms: Dictionary, cache: SolverCache, width: int) -> ReachGraph.Report:
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	abilities.imprint_width = width
	var graph := ReachGraph.new(rooms, _cfg, abilities)
	graph.cache = cache
	return graph.analyze("1")


func _same(a: ReachGraph.Report, b: ReachGraph.Report) -> bool:
	return a.errors == b.errors and a.warnings == b.warnings and a.reached_ledges == b.reached_ledges and a.total_ledges == b.total_ledges and a.unreached.size() == b.unreached.size() and a.traps.size() == b.traps.size() and a.one_way.size() == b.one_way.size() and a.pickups == b.pickups


## Two rooms side by side. Room 1 is a floor with a pit of spikes in it, a start
## on the left, and a door on the far side to room 2. `second` adds cells to
## room 2, and `with_second` false leaves it out.
func _world(second := {}, with_second := true, header := "", first_marks := {}) -> Dictionary:
	var first := {Vector2i(2, 16): "P", Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	for x in range(9, 21):
		first[Vector2i(x, 16)] = "^"
	first.merge(first_marks, true)
	var entries := [{"id": "1", "grid_pos": Vector2i(0, 0), "text": header + _room(first)}]
	if with_second:
		var far := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}
		far.merge(second, true)
		entries.append({"id": "2", "grid_pos": Vector2i(1, 0), "text": _room(far)})
	var errors: Array[String] = []
	var built := RoomParser.build(entries, "1", errors)
	if not errors.is_empty():
		print("  world did not load: ", errors)
	return built["rooms"]


func _room(marks: Dictionary) -> String:
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += marks.get(Vector2i(x, y), "#" if edge else ".")
		rows.append(row)
	return "\n".join(rows) + "\n"


func _clear() -> void:
	var path := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(path):
		for file in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
	else:
		DirAccess.make_dir_recursive_absolute(path)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
