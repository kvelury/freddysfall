extends SceneTree

## The solver with Imprint. A room behind a pit of spikes too wide to jump is
## open only to a player who has found Imprint, and the validator says which
## pickup it needs. Worlds are built from strings.

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	var ok := true
	ok = _gate() and ok
	ok = _progression() and ok
	ok = _forbidden() and ok
	print("IMPRINTSOLVER %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _gate() -> bool:
	var ok := true
	var rooms := _world({})
	var locked := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = _check(_has(locked.errors, "Room 2 cannot be reached"), "without Imprint the room past the pit is out of reach %s" % [locked.errors]) and ok

	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var started := Time.get_ticks_msec()
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	ok = _check(open.errors.is_empty(), "with Imprint it is reachable, using a platform over the spikes %s" % [open.errors]) and ok
	ok = _check(seconds < 10.0, "and the search is fast enough (%.1f s)" % seconds) and ok

	# A platform that breaks too soon is no use: each jump has to fit in its life.
	abilities.imprint_duration = 1.0
	var brief := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(_has(brief.errors, "Room 2 cannot be reached"), "a platform that lasts one second is not enough to cross %s" % [brief.errors]) and ok
	return ok


func _progression() -> bool:
	var ok := true
	# The pickup that gives Imprint is on the near side.
	var rooms := _world({Vector2i(4, 16): "U"}, "legend:\n  U = pickup id=key upgrade=imprint\n---\n")
	var base := Abilities.new()
	var graph := ReachGraph.new(rooms, _cfg, base)
	var report := graph.solve("1")
	ok = _check(report.errors.is_empty(), "taking the pickup opens the way %s" % [report.errors]) and ok
	ok = _check(report.needs.get("1") == [], "room 1 needs nothing (%s)" % [report.needs.get("1")]) and ok
	ok = _check(report.needs.get("2") == ["key"], "room 2 needs the pickup that gives Imprint (%s)" % [report.needs.get("2")]) and ok
	ok = _check(not base.imprint_unlocked and not graph.abilities.imprint_unlocked, "and solving leaves the starting abilities alone") and ok

	# A reward on the far side needs Imprint too, and says so.
	rooms = _world({Vector2i(4, 16): "U", Vector2i(26, 16): "V"}, "legend:\n  U = pickup id=key upgrade=imprint\n  V = pickup id=wide upgrade=imprint_width value=3\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(report.errors.is_empty() and report.needs.get("pickup|wide") == ["key"] and not report.needs.has("pickup|key"), "a pickup across the pit needs the Imprint pickup, which needs nothing (%s)" % [report.needs]) and ok

	# The same pickup on the far side can never be taken.
	rooms = _world({Vector2i(26, 16): "U"}, "legend:\n  U = pickup id=key upgrade=imprint\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(_has(report.errors, "Room 2 cannot be reached") and _has(report.errors, "pickup key"), "a pickup behind its own gate is an error %s" % [report.errors]) and ok
	return ok


func _forbidden() -> bool:
	var ok := true
	# ~ cells over the whole pit leave no place for a platform.
	var marks := {}
	for y in range(8, 17):
		for x in range(9, 21):
			if y != 16:
				marks[Vector2i(x, y)] = "~"
	var rooms := _world(marks)
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var report := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(_has(report.errors, "Room 2 cannot be reached"), "~ cells over the pit forbid the platform, and the room stays shut %s" % [report.errors]) and ok
	return ok


## Two rooms side by side. Room 1 is a floor with a pit of spikes 12 cells wide
## in it, a start on the left, and a door on the far side that leads to room 2.
func _world(marks: Dictionary, header := "") -> Dictionary:
	var first := {Vector2i(2, 16): "P", Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	for x in range(9, 21):
		first[Vector2i(x, 16)] = "^"
	first.merge(marks, true)
	var errors: Array[String] = []
	var built := RoomParser.build([
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": header + _room(first)},
		{"id": "2", "grid_pos": Vector2i(1, 0), "text": _room({Vector2i(0, 15): "X", Vector2i(0, 16): "X"})},
	], "1", errors)
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


func _has(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
