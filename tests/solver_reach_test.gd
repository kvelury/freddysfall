extends TestCase

## Small worlds built to be wrong in one way each, solved: shelves out of reach,
## a trap, a door in the sky, shafts, spikes, pickups. (tests/reach_test.gd covers
## the room loader, links and camera.) Optional: it is run by `tools/check.sh --solver`.

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres") as MovementConfig
	var ok := _reach_cases()
	ok = _too_many_jumps() and ok
	print("RESULT %s" % ("pass" if ok and passed() else "fail"))
	quit(0 if ok and passed() else 1)


## Small worlds built to be wrong in one way each.
func _reach_cases() -> bool:
	var ok := true

	var shelves := {}
	_fill(shelves, 10, 6, 14, 6)
	_fill(shelves, 20, 13, 24, 13)
	var report := _solve([_entry("1", Vector2i(0, 0), _box(shelves))])
	ok = check(report.errors.is_empty(), "shelves load and solve without errors %s" % [report.errors]) and ok
	ok = check(report.unreached.size() == 1 and report.unreached[0].row == 5, "a shelf 100 px up cannot be reached, a 40 px one can (%d unreached)" % report.unreached.size()) and ok
	ok = check(report.warnings.size() == 1 and report.warnings[0].contains("row 5"), "an unreachable ledge is only a warning %s" % [report.warnings]) and ok

	# Two plateaus with a valley between that is deeper than a jump is tall.
	var valley := {}
	_fill(valley, 1, 10, 9, 16)
	_fill(valley, 14, 10, 30, 16)
	valley[Vector2i(3, 9)] = "P"
	report = _solve([_entry("1", Vector2i(0, 0), _box(valley, false))])
	ok = check(report.traps.size() == 1 and report.traps[0].row == 16, "a valley too deep to climb out of is a trap (%d traps)" % report.traps.size()) and ok
	ok = check(_has_line(report.errors, "trap"), "a trap is an error") and ok
	ok = check(report.unreached.is_empty(), "the far plateau is jumpable across the valley") and ok

	var high_door := {Vector2i(31, 2): "X", Vector2i(31, 3): "X"}
	var low_door := {Vector2i(0, 2): "X", Vector2i(0, 3): "X"}
	report = _solve([_entry("1", Vector2i(0, 0), _box(high_door)), _entry("2", Vector2i(1, 0), _box(low_door, false))])
	ok = check(_has_line(report.errors, "door at") and _has_line(report.errors, "Room 2 cannot be reached"), "a door in the sky strands the room behind it %s" % [report.errors]) and ok

	var floor_a := {Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	var floor_b := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}
	report = _solve([_entry("1", Vector2i(0, 0), _box(floor_a)), _entry("2", Vector2i(1, 0), _box(floor_b, false))])
	ok = check(report.errors.is_empty() and report.traps.is_empty(), "floor-level doors connect two rooms both ways %s" % [report.errors]) and ok
	ok = check(report.reached_ledges == 2 and report.total_ledges == 2, "both floors are reached (%d of %d)" % [report.reached_ledges, report.total_ledges]) and ok

	# A shaft with a hole in room 1's floor and nothing to climb in room 2.
	var hole := _cells_in(6, 17, 12, 17, "X")
	var ceiling := _cells_in(6, 0, 12, 0, "X")
	report = _solve([_entry("1", Vector2i(0, 0), _box(hole)), _entry("2", Vector2i(0, 1), _box(ceiling, false))])
	ok = check(report.traps.size() == 1 and report.traps[0].room_id == "2", "a shaft with no way back up is a trap (%d traps)" % report.traps.size()) and ok

	# The same shaft with a zigzag of platforms up to the ceiling hole.
	var stairs := ceiling.duplicate()
	stairs.merge(_cells_in(14, 13, 19, 13, "#"))
	stairs.merge(_cells_in(5, 9, 10, 9, "#"))
	stairs.merge(_cells_in(14, 5, 19, 5, "#"))
	# Start on the right of the hole, the side the climb comes out on. A start on
	# the left would be cut off from it by a hole too wide to jump.
	var home := hole.duplicate()
	home[Vector2i(20, 16)] = "P"
	report = _solve([_entry("1", Vector2i(0, 0), _box(home, false)), _entry("2", Vector2i(0, 1), _box(stairs, false))])
	ok = check(report.errors.is_empty() and report.traps.is_empty(), "a zigzag of platforms makes the shaft climbable both ways %s" % [report.errors]) and ok

	# A door that drops everyone onto spikes.
	var spikes := ceiling.duplicate()
	spikes.merge(_cells_in(1, 16, 30, 16, "^"))
	report = _solve([_entry("1", Vector2i(0, 0), _box(hole)), _entry("2", Vector2i(0, 1), _box(spikes, false))])
	ok = check(_has_line(report.errors, "never lands on anything"), "a door onto nothing but spikes is an error %s" % [report.errors]) and ok

	# Spikes in the floor: a narrow patch can be jumped, a wide one cannot.
	report = _solve([_entry("1", Vector2i(0, 0), _box(_cells_in(10, 16, 13, 16, "^")))])
	ok = check(report.errors.is_empty() and report.unreached.is_empty() and report.total_ledges == 2, "a 4 cell patch of spikes can be jumped (%d ledges, %d unreached)" % [report.total_ledges, report.unreached.size()]) and ok
	report = _solve([_entry("1", Vector2i(0, 0), _box(_cells_in(8, 16, 26, 16, "^")))])
	ok = check(report.unreached.size() == 1 and report.unreached[0].x0 == 27, "a 19 cell patch of spikes cannot (%d unreached)" % report.unreached.size()) and ok

	# Pickups: one on the floor and one a jump above it are collected; one
	# eight cells up is not, and that is an error.
	var legend := "legend:\n  U = pickup id=floor upgrade=tongue_cooldown value=0.5\n  V = pickup id=hop upgrade=tongue_speed value=700\n  W = pickup id=high upgrade=tongue_length value=120\n---\n"
	report = _solve([_entry("1", Vector2i(0, 0), legend + _box({Vector2i(10, 16): "U", Vector2i(20, 13): "V", Vector2i(26, 8): "W"}))])
	var taken := {}
	for pickup in report.pickups:
		taken[pickup.id] = pickup.reached
	ok = check(taken == {"floor": true, "hop": true, "high": false}, "a pickup on the floor or a hop up is reached, one eight cells up is not %s" % [taken]) and ok
	ok = check(_has_line(report.errors, "pickup high"), "and the one out of reach is an error %s" % [report.errors]) and ok
	return ok


## Two air jumps is more than the solver's plans cover, so a solve says so
## instead of reporting a world those jumps would open as shut.
func _too_many_jumps() -> bool:
	var built := _world([_entry("1", Vector2i(0, 0), _box())])
	var graph := ReachGraph.new(built["rooms"], _cfg)
	graph.abilities.air_jumps = 2
	var report := graph.solve("1")
	var said := false
	for line in report.errors:
		said = said or String(line).contains("at most one air jump")
	return check(said, "two air jumps is reported, not solved as one (%s)" % [report.errors])


func _solve(entries: Array) -> ReachGraph.Report:
	var built := _world(entries)
	if not built["errors"].is_empty():
		print("  world did not load: ", built["errors"])
	return ReachGraph.new(built["rooms"], _cfg).analyze("1")


## A 32 x 18 room with a wall around it. `cells` overrides single cells.
func _box(cells: Dictionary = {}, spawn := true) -> String:
	var lines: Array[String] = []
	for y in 18:
		var line := ""
		for x in 32:
			var glyph := "#" if x == 0 or y == 0 or x == 31 or y == 17 else "."
			if spawn and x == 2 and y == 16:
				glyph = "P"
			line += String(cells.get(Vector2i(x, y), glyph))
		lines.append(line)
	return "\n".join(lines)


func _entry(id: String, pos: Vector2i, text: String) -> Dictionary:
	return {"id": id, "grid_pos": pos, "text": text}


func _world(entries: Array, start := "1") -> Dictionary:
	var errors: Array[String] = []
	var built := RoomParser.build(entries, start, errors)
	built["errors"] = errors
	return built


## Fills a block of cells with solid.
func _fill(cells: Dictionary, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells[Vector2i(x, y)] = "#"


func _has_line(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	print("  no line containing '%s' in %s" % [fragment, lines])
	return false


func _cells_in(x0: int, y0: int, x1: int, y1: int, glyph: String) -> Dictionary:
	var cells := {}
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells[Vector2i(x, y)] = glyph
	return cells
