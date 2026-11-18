extends TestCase

## The solver's view of moving platforms: a ledge only a ride reaches is
## reached, a platform out of reach is warned about, and an Imprint is refused
## on a track. (tests/platform_test.gd covers the format, path, play and parity.)
## Optional: it is run by `tools/check.sh --solver`.


func _initialize() -> void:
	watchdog(120.0)
	finish("SOLVER PLATFORM", _solver())


func _solver() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	# A ledge 8 cells up on the right is too high to jump to, but a platform
	# that rises beside it brings it within a jump.
	var marks := {Vector2i(0, 9): "#........................#######", Vector2i(0, 15): "#.................LLL..........#"}
	for y in range(10, 15):
		marks[Vector2i(0, y)] = "#.................|||..........#"
	var rooms := _rooms(marks, "  L = platform id=lift speed=40\n")
	var graph := ReachGraph.new(rooms, cfg)
	var report := graph.analyze("1")
	var high: ReachGraph.Ledge = null
	var lift: ReachGraph.Ledge = null
	for ledge in graph.ledges_in("1"):
		if ledge.row == 8 and not ledge.moving:
			high = ledge
		if ledge.moving:
			lift = ledge
	ok = check(lift != null and report.reached.has(lift), "the rising platform is reached from the floor") and ok
	ok = check(high != null and report.reached.has(high), "and the high ledge is reached by riding it") and ok
	ok = check(report.errors.is_empty(), "with no errors, so there is a way back down from both %s" % [report.errors]) and ok
	var plain := {Vector2i(0, 9): "#........................#######"}
	rooms = _rooms(plain, "")
	graph = ReachGraph.new(rooms, cfg)
	report = graph.analyze("1")
	var reached_high := false
	for ledge in graph.ledges_in("1"):
		if ledge.row == 8 and report.reached.has(ledge):
			reached_high = true
	ok = check(not reached_high, "without the platform the high ledge is out of reach") and ok
	# A platform nine cells up cannot be reached.
	rooms = _rooms({Vector2i(0, 8): "#.........LLL--------..........#"}, "  L = platform id=sky speed=60\n")
	graph = ReachGraph.new(rooms, cfg)
	report = graph.analyze("1")
	ok = check(_has(report.warnings, "the moving platform sky cannot be reached"), "a platform out of reach is a warning %s" % [report.warnings]) and ok
	# Imprint is refused on a track and in the row above it.
	var info: RoomInfo = rooms["1"]
	var body := Rect2(20, 160, 10, 10)
	ok = check(ImprintRules.check(info, Vector2i(15, 8), 2, body) == "platform" and ImprintRules.check(info, Vector2i(15, 7), 2, body) == "platform", "an Imprint cannot go on a track or in the row above it") and ok
	ok = check(ImprintRules.check(info, Vector2i(15, 10), 2, body).is_empty(), "but can go below it") and ok
	return ok


func _rooms(rows: Dictionary, legend: String) -> Dictionary:
	var errors: Array[String] = []
	var header := "" if legend.is_empty() else "legend:\n" + legend + "---\n"
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": header + _room(rows, Vector2i(2, 16))}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
	return built["rooms"]


## A walled one-screen room. `rows` maps Vector2i(0, y) to a whole row; a
## start goes at `spawn` unless it is off the grid.
func _room(rows: Dictionary, spawn: Vector2i) -> String:
	var out: Array[String] = []
	for y in 18:
		var row := ""
		if rows.has(Vector2i(0, y)):
			row = rows[Vector2i(0, y)]
		else:
			for x in 32:
				row += "#" if x == 0 or y == 0 or x == 31 or y == 17 else "."
		if y == spawn.y and spawn.x >= 0:
			row = row.substr(0, spawn.x) + "P" + row.substr(spawn.x + 1)
		out.append(row)
	return "\n".join(out) + "\n"


func _has(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	print("  nothing containing '%s' in %s" % [fragment, lines])
	return false
