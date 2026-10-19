extends SceneTree

var _cfg: MovementConfig


func _initialize() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	if cfg == null:
		print("FAIL movement.tres did not load")
		return false
	_cfg = cfg
	var passed := true
	passed = _feel(cfg) and passed
	passed = _room_shapes(data) and passed
	passed = _links(data) and passed
	passed = _reach_world(data) and passed
	passed = _reach_cases() and passed
	passed = _loader() and passed
	passed = _crossing(data) and passed
	passed = _camera() and passed
	print("RESULT %s" % ("pass" if passed else "fail"))
	return passed


func _feel(cfg: MovementConfig) -> bool:
	var floor_only: Array[Rect2] = [Rect2(0, 170, 800, 10)]
	var full := MovementSim.simulate_jump(cfg, floor_only, Vector2(40, 165), Vector2(cfg.run_speed, 0), 1.0, 90)
	var tap := MovementSim.simulate_jump(cfg, floor_only, Vector2(40, 165), Vector2(cfg.run_speed, 0), 1.0, 2)
	var rise := 170.0 - float(full["min_feet"])
	var tap_rise := 170.0 - float(tap["min_feet"])
	var dist := float(full["position"].x) - 40.0
	var ok := true
	ok = _check(rise >= 44.0 and rise <= 52.0, "full jump height %.1f px (about 4.8 cells)" % rise) and ok
	ok = _check(tap_rise < 20.0, "tap jump stays short (%.1f px)" % tap_rise) and ok
	ok = _check(dist >= 50.0 and dist <= 80.0, "running jump travels %.1f px" % dist) and ok
	return ok


func _room_shapes(data) -> bool:
	var info: RoomInfo = data.get_room("1")
	var ok := true
	ok = _check(_has_rect(info, Rect2i(6, 13, 5, 1)), "room 1 left platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(21, 13, 5, 1)), "room 1 right platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(14, 9, 5, 1)), "room 1 middle platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(23, 5, 9, 1)), "room 1 top platform rect") and ok
	var wide: RoomInfo = data.get_room("3")
	var room := Room.new()
	room.build(wide)
	var chunks := 0
	for child in room.get_children():
		if String(child.name).begins_with("Chunk_"):
			chunks += 1
	ok = _check(chunks == 2, "room 3 builds one chunk per screen (%d)" % chunks) and ok
	room.free()
	return ok


func _links(data) -> bool:
	var a: RoomInfo = data.get_room("1")
	var b: RoomInfo = data.get_room("2")
	var ok := true
	ok = _check(a.exit_on("right").dest_id == "2", "room 1 right exit leads to 2") and ok
	ok = _check(b.exit_on("left").dest_id == "1", "room 2 left exit leads to 1") and ok
	var c: RoomInfo = data.get_room("3")
	ok = _check(c.screens == Vector2i(2, 1), "room 3 spans two screens") and ok
	ok = _check(c.bounds_cells == Rect2i(0, 0, 64, 18), "room 3 bounds cover the whole room") and ok
	ok = _check(data.id_at(Vector2i(2, 0)) == "3" and data.id_at(Vector2i(3, 0)) == "3", "room 3 occupies both of its screens") and ok
	var side := b.exit_on("right")
	var side_rect := side.rect
	ok = _check(b.exit_on("down") == null, "room 2 floor stays solid") and ok
	ok = _check(side.dest_id == "3", "room 2 floor exit leads to 3") and ok
	ok = _check(side_rect.position.y == 15 and side_rect.size == Vector2i(1, 2), "room 2 exit is a floor-level side door (%s)" % side_rect) and ok
	var back := c.exit_on("left")
	var back_rect := back.rect
	ok = _check(c.exit_on("up") == null, "room 3 ceiling stays solid") and ok
	ok = _check(back.dest_id == "2", "room 3 side entrance leads back to 2") and ok
	ok = _check(back_rect.position.y == 15 and back_rect.size == Vector2i(1, 2), "room 3 entrance is a floor-level side door (%s)" % back_rect) and ok
	return ok


## Where a body appears on the far side of a door.
func _crossing(data) -> bool:
	var ok := true
	var one: RoomInfo = data.get_room("1")
	var two: RoomInfo = data.get_room("2")
	var three: RoomInfo = data.get_room("3")
	var run := Vector2(90.0, 0.0)

	# Same place along the wall, same velocity, and just clear of the far door.
	var across := Door.crossing(one.exit_on("right"), two, Vector2(301.0, 35.0), run)
	ok = _check(across["position"] == Vector2(339.5, 35.0), "crossing room 1's door keeps height and pushes in (%s)" % across["position"]) and ok
	ok = _check(across["velocity"] == run, "crossing keeps velocity") and ok
	var body := Rect2(across["position"] - Vector2(5, 5), Vector2(10, 10))
	var trigger := two.exit_on("left").trigger_rect()
	ok = _check(not Rect2(trigger.position + Vector2(320, 0), trigger.size).intersects(body), "a body that crossed is clear of the far trigger") and ok

	# A door the body is not level with: it is carried along the wall to the far door.
	var shifted := Door.crossing(two.exit_on("right"), three, Vector2(301.0, 145.0), run)
	ok = _check(shifted["position"] == Vector2(659.5, 155.0), "crossing is clamped into the far door's rows (%s)" % shifted["position"]) and ok

	# Up and down, between two rooms in a column.
	var shaft := _world([
		_entry("1", Vector2i(0, 1), _box(_cells_in(6, 0, 12, 0, "X"))),
		_entry("2", Vector2i(0, 0), _box(_cells_in(6, 17, 12, 17, "X"), false)),
	], "1")
	var low: RoomInfo = shaft["rooms"]["1"]
	var high: RoomInfo = shaft["rooms"]["2"]
	ok = _check(shaft["errors"].is_empty(), "a two-room shaft loads clean %s" % [shaft["errors"]]) and ok
	var rising := Door.crossing(low.exit_on("up"), high, Vector2(95.0, 195.0), Vector2(0.0, -50.0))
	ok = _check(rising["position"] == Vector2(95.0, 160.5), "going up pushes into the room above (%s)" % rising["position"]) and ok
	ok = _check(rising["velocity"].y == -Door.UP_BOOST, "going up slowly is lifted to the minimum rise (%s)" % rising["velocity"]) and ok
	var leaping := Door.crossing(low.exit_on("up"), high, Vector2(95.0, 195.0), Vector2(0.0, -300.0))
	ok = _check(leaping["velocity"].y == -300.0, "going up fast is not slowed") and ok
	var edge := Door.crossing(low.exit_on("up"), high, Vector2(20.0, 195.0), Vector2.ZERO)
	ok = _check(edge["position"].x == 65.0, "crossing is clamped into the far door's columns (%s)" % edge["position"]) and ok
	var falling := Door.crossing(high.exit_on("down"), low, Vector2(95.0, 170.0), Vector2(30.0, 200.0))
	ok = _check(falling["position"] == Vector2(95.0, 199.5) and falling["velocity"] == Vector2(30.0, 200.0), "going down keeps velocity and drops in (%s)" % falling["position"]) and ok

	# A wall right behind the far door shortens the push instead of burying the body.
	var tight := _cells_in(0, 15, 0, 16, "X")
	tight.merge(_cells_in(1, 15, 3, 16, "#"))
	var walled := _world([
		_entry("1", Vector2i(0, 0), _box(_cells_in(31, 15, 31, 16, "X"))),
		_entry("2", Vector2i(1, 0), _box(tight, false)),
	], "1")
	var behind: RoomInfo = walled["rooms"]["2"]
	var squeezed := Door.crossing((walled["rooms"]["1"] as RoomInfo).exit_on("right"), behind, Vector2(301.0, 165.0), run)
	ok = _check(squeezed["position"].x == 325.0, "a wall behind the door shortens the push (%s)" % squeezed["position"]) and ok
	return ok


func _cells_in(x0: int, y0: int, x1: int, y1: int, glyph: String) -> Dictionary:
	var cells := {}
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells[Vector2i(x, y)] = glyph
	return cells


## Builds worlds from strings so every way a room file can be wrong is checked
## without touching the disk.
func _loader() -> bool:
	var ok := true
	var clean := _world([_entry("1", Vector2i(0, 0), _box())])
	ok = _check(clean["errors"].is_empty(), "a plain box loads clean %s" % [clean["errors"]]) and ok

	var bad_glyph := _world([_entry("1", Vector2i(0, 0), _box({Vector2i(5, 5): "?"}))])
	ok = _check(_has_error(bad_glyph["errors"], "not a known glyph"), "an unknown glyph is an error") and ok

	var open_edge := _world([_entry("1", Vector2i(0, 0), _box({Vector2i(0, 5): "."}))])
	ok = _check(_has_error(open_edge["errors"], "outer wall must be"), "an open edge cell is an error") and ok

	var open_row := {}
	for x in range(1, 31):
		open_row[Vector2i(x, 0)] = "."
	var many := _world([_entry("1", Vector2i(0, 0), _box(open_row))])
	ok = _check(many["errors"].size() == RoomParser.MAX_PER_KIND + 1 and _has_error(many["errors"], "more like that"), "a whole open wall is capped (%d lines)" % many["errors"].size()) and ok

	var wrong_size := _world([_entry("1", Vector2i(0, 0), _box().replace("\n", "#\n"))])
	ok = _check(_has_error(wrong_size["errors"], "whole number of"), "a room that is not whole screens is an error") and ok

	var no_spawn := _world([_entry("1", Vector2i(0, 0), _box({}, false))])
	ok = _check(_has_error(no_spawn["errors"], "has no P"), "the start room needs a P") and ok

	var no_start := _world([_entry("1", Vector2i(0, 0), _box())], "9")
	ok = _check(_has_error(no_start["errors"], "not in the world"), "an unlisted start room is an error") and ok

	var twice := _world([_entry("1", Vector2i(0, 0), _box()), _entry("1", Vector2i(1, 0), _box())])
	ok = _check(_has_error(twice["errors"], "listed twice"), "a repeated room id is an error") and ok

	var overlap := _world([_entry("1", Vector2i(0, 0), _box()), _entry("2", Vector2i(0, 0), _box({}, false))])
	ok = _check(_has_error(overlap["errors"], "overlaps"), "two rooms on one screen is an error") and ok

	var door := {Vector2i(31, 5): "X", Vector2i(31, 6): "X"}
	var dead_end := _world([_entry("1", Vector2i(0, 0), _box(door))])
	var lone: RoomInfo = dead_end["rooms"]["1"]
	ok = _check(dead_end["errors"].is_empty(), "a door to nowhere is not an error %s" % [dead_end["errors"]]) and ok
	ok = _check(lone.exits.is_empty() and lone.sealed == [Rect2i(31, 5, 1, 2)], "a door to nowhere is sealed (%s)" % [lone.sealed]) and ok
	ok = _check(lone.is_solid(31, 5) and lone.is_solid(31, 6), "a sealed door is solid") and ok
	ok = _check(_covers(lone.solids, Vector2i(31, 5)), "a sealed door is in the collision rects") and ok

	var left_door := {Vector2i(0, 5): "X", Vector2i(0, 6): "X"}
	var paired := _world([_entry("1", Vector2i(0, 0), _box(door)), _entry("2", Vector2i(1, 0), _box(left_door, false))])
	var first: RoomInfo = paired["rooms"]["1"]
	ok = _check(paired["errors"].is_empty() and first.exit_on("right").dest_id == "2", "facing doors pair up %s" % [paired["errors"]]) and ok
	ok = _check(first.exit_on("right").dest_rect == Rect2i(0, 5, 1, 2), "a door knows the rect of the door it meets") and ok

	# A room with no P is started in beside its first door.
	var west_door := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}
	var east_door := {Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	var pair := _world([_entry("1", Vector2i(1, 0), _box(west_door)), _entry("2", Vector2i(0, 0), _box(east_door, false))])
	ok = _check(pair["errors"].is_empty() and (pair["rooms"]["2"] as RoomInfo).start_position() == Vector2(300.5, 165), "a room without P starts just inside its door (%s)" % (pair["rooms"]["2"] as RoomInfo).start_position()) and ok
	ok = _check((pair["rooms"]["1"] as RoomInfo).start_position() == Vector2(25, 165), "a room with P starts on it") and ok

	var unmatched := _world([_entry("1", Vector2i(0, 0), _box(door)), _entry("2", Vector2i(1, 0), _box({}, false))])
	var stuck: RoomInfo = unmatched["rooms"]["1"]
	ok = _check(_has_error(unmatched["errors"], "0 matching doors"), "a door facing a wall is an error") and ok
	ok = _check(stuck.exits.is_empty() and stuck.is_solid(31, 5), "a door facing a wall is sealed") and ok
	return ok


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


func _has_error(errors: Array, fragment: String) -> bool:
	for message in errors:
		if String(message).contains(fragment):
			return true
	print("  no error containing '%s' in %s" % [fragment, errors])
	return false


func _covers(rects: Array[Rect2i], cell: Vector2i) -> bool:
	for rect in rects:
		if rect.has_point(cell):
			return true
	return false


## The real world has to solve completely: every room, door and ledge
## reachable, and nowhere to get stuck.
func _reach_world(data) -> bool:
	var report := ReachGraph.new(data.rooms, _cfg).solve(data.start_room)
	var ok := true
	ok = _check(report.errors.is_empty(), "the world has no reach errors %s" % [report.errors]) and ok
	ok = _check(report.reached_ledges == report.total_ledges and report.total_ledges > 0, "every ledge in the world is reachable (%d of %d)" % [report.reached_ledges, report.total_ledges]) and ok
	ok = _check(report.traps.is_empty(), "there is nowhere to get stuck") and ok
	return ok


## Small worlds built to be wrong in one way each.
func _reach_cases() -> bool:
	var ok := true

	var shelves := {}
	_fill(shelves, 10, 6, 14, 6)
	_fill(shelves, 20, 13, 24, 13)
	var report := _solve([_entry("1", Vector2i(0, 0), _box(shelves))])
	ok = _check(report.errors.is_empty(), "shelves load and solve without errors %s" % [report.errors]) and ok
	ok = _check(report.unreached.size() == 1 and report.unreached[0].row == 5, "a shelf 100 px up cannot be reached, a 40 px one can (%d unreached)" % report.unreached.size()) and ok
	ok = _check(report.warnings.size() == 1 and report.warnings[0].contains("row 5"), "an unreachable ledge is only a warning %s" % [report.warnings]) and ok

	# Two plateaus with a valley between that is deeper than a jump is tall.
	var valley := {}
	_fill(valley, 1, 10, 9, 16)
	_fill(valley, 14, 10, 30, 16)
	valley[Vector2i(3, 9)] = "P"
	report = _solve([_entry("1", Vector2i(0, 0), _box(valley, false))])
	ok = _check(report.traps.size() == 1 and report.traps[0].row == 16, "a valley too deep to climb out of is a trap (%d traps)" % report.traps.size()) and ok
	ok = _check(_has_line(report.errors, "trap"), "a trap is an error") and ok
	ok = _check(report.unreached.is_empty(), "the far plateau is jumpable across the valley") and ok

	var high_door := {Vector2i(31, 2): "X", Vector2i(31, 3): "X"}
	var low_door := {Vector2i(0, 2): "X", Vector2i(0, 3): "X"}
	report = _solve([_entry("1", Vector2i(0, 0), _box(high_door)), _entry("2", Vector2i(1, 0), _box(low_door, false))])
	ok = _check(_has_line(report.errors, "door at") and _has_line(report.errors, "Room 2 cannot be reached"), "a door in the sky strands the room behind it %s" % [report.errors]) and ok

	var floor_a := {Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	var floor_b := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}
	report = _solve([_entry("1", Vector2i(0, 0), _box(floor_a)), _entry("2", Vector2i(1, 0), _box(floor_b, false))])
	ok = _check(report.errors.is_empty() and report.traps.is_empty(), "floor-level doors connect two rooms both ways %s" % [report.errors]) and ok
	ok = _check(report.reached_ledges == 2 and report.total_ledges == 2, "both floors are reached (%d of %d)" % [report.reached_ledges, report.total_ledges]) and ok

	# A shaft with a hole in room 1's floor and nothing to climb in room 2.
	var hole := _cells_in(6, 17, 12, 17, "X")
	var ceiling := _cells_in(6, 0, 12, 0, "X")
	report = _solve([_entry("1", Vector2i(0, 0), _box(hole)), _entry("2", Vector2i(0, 1), _box(ceiling, false))])
	ok = _check(report.traps.size() == 1 and report.traps[0].room_id == "2", "a shaft with no way back up is a trap (%d traps)" % report.traps.size()) and ok

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
	ok = _check(report.errors.is_empty() and report.traps.is_empty(), "a zigzag of platforms makes the shaft climbable both ways %s" % [report.errors]) and ok

	# A door that drops everyone onto spikes.
	var spikes := ceiling.duplicate()
	spikes.merge(_cells_in(1, 16, 30, 16, "^"))
	report = _solve([_entry("1", Vector2i(0, 0), _box(hole)), _entry("2", Vector2i(0, 1), _box(spikes, false))])
	ok = _check(_has_line(report.errors, "never lands on anything"), "a door onto nothing but spikes is an error %s" % [report.errors]) and ok

	# Spikes in the floor: a narrow patch can be jumped, a wide one cannot.
	report = _solve([_entry("1", Vector2i(0, 0), _box(_cells_in(10, 16, 13, 16, "^")))])
	ok = _check(report.errors.is_empty() and report.unreached.is_empty() and report.total_ledges == 2, "a 4 cell patch of spikes can be jumped (%d ledges, %d unreached)" % [report.total_ledges, report.unreached.size()]) and ok
	report = _solve([_entry("1", Vector2i(0, 0), _box(_cells_in(8, 16, 26, 16, "^")))])
	ok = _check(report.unreached.size() == 1 and report.unreached[0].x0 == 27, "a 19 cell patch of spikes cannot (%d unreached)" % report.unreached.size()) and ok

	# Pickups: one on the floor and one a jump above it are collected; one
	# eight cells up is not, and that is an error.
	var legend := "legend:\n  U = pickup id=floor upgrade=imprint_width value=3\n  V = pickup id=hop upgrade=imprint_duration value=6\n  W = pickup id=high upgrade=imprint_max_active value=2\n---\n"
	report = _solve([_entry("1", Vector2i(0, 0), legend + _box({Vector2i(10, 16): "U", Vector2i(20, 13): "V", Vector2i(26, 8): "W"}))])
	var taken := {}
	for pickup in report.pickups:
		taken[pickup["id"]] = pickup["reached"]
	ok = _check(taken == {"floor": true, "hop": true, "high": false}, "a pickup on the floor or a hop up is reached, one eight cells up is not %s" % [taken]) and ok
	ok = _check(_has_line(report.errors, "pickup high"), "and the one out of reach is an error %s" % [report.errors]) and ok
	return ok


func _solve(entries: Array) -> ReachGraph.Report:
	var built := _world(entries)
	if not built["errors"].is_empty():
		print("  world did not load: ", built["errors"])
	return ReachGraph.new(built["rooms"], _cfg).analyze("1")


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


func _camera() -> bool:
	var ok := true
	var one := Grid.camera_focus(Vector2(320, 0), Vector2(320, 180), Vector2(400, 90))
	ok = _check(one == Vector2(480, 90), "one-screen room keeps the camera centered (%s)" % one) and ok
	var wide := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(900, 200))
	ok = _check(wide == Vector2(800, 270), "two-screen room clamps the camera (%s)" % wide) and ok
	var followed := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(600, 250))
	ok = _check(followed == Vector2(600, 270), "two-screen room follows within the span (%s)" % followed) and ok
	return ok


func _has_rect(info: RoomInfo, expected: Rect2i) -> bool:
	for cell in info.solids:
		if cell == expected:
			return true
	print("  solids: ", info.solids)
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
