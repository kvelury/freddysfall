extends SceneTree

## Spinners: the room format (a rectangle of the glyph, spikes= naming the spiked
## parts, a clear sweep), the blocks' places at known ticks (whole turns return,
## quarter turns swap the axes, counter-clockwise on screen), spiked blocks kill
## and safe ones carry.

const DT := 1.0 / 60.0
const LEGEND := "legend:\n  R = spinner id=sp period=4 spikes=bottom+top_left\n---\n"


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	var ok := true
	ok = _parser() and ok
	ok = _path() and ok
	ok = _sweep_coverage() and ok
	ok = _clearance() and ok
	ok = _sim() and ok
	print("SPINNER %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _check(condition: bool, message: String) -> bool:
	print("%s   %s" % ["ok" if condition else "FAIL", message])
	return condition


static func _rows(bar_row := 9, wall_at := -1) -> Array[String]:
	var rows: Array[String] = []
	for y in 18:
		rows.append("#" + ".".repeat(30) + "#")
	rows[0] = "#".repeat(32)
	rows[17] = "#".repeat(32)
	rows[bar_row] = "#" + ".".repeat(10) + "R".repeat(11) + ".".repeat(9) + "#"
	rows[bar_row + 1] = rows[bar_row]
	if wall_at >= 0:
		rows[wall_at] = "#" + ".".repeat(10) + "#" + ".".repeat(19) + "#"
	return rows


static func _parse(rows: Array[String], legend := LEGEND) -> Array:
	var errors: Array[String] = []
	var info := RoomParser.parse_room("t", Vector2i.ZERO, legend + "\n".join(rows), errors)
	return [info, errors]


func _parser() -> bool:
	var ok := true
	var made := _parse(_rows(8))
	var info: RoomInfo = made[0]
	ok = _check(info != null and (made[1] as Array).is_empty(), "an 11 x 2 bar with room to turn loads (%s)" % [made[1]]) and ok
	if info != null and not info.spinners.is_empty():
		var path := info.spinners[0]
		ok = _check(path.body_count() == 22 and info.movers.size() == 1 and info.platforms.is_empty(), "22 blocks, one mover") and ok
		var spikes := 0
		for body in path.body_count():
			if path.is_hazard(body):
				spikes += 1
		ok = _check(spikes == 11 + 5, "the bottom row (11) and the left of the top (5) are spiked (%d)" % spikes) and ok
	var rows := _rows(8)
	rows[8] = "#" + ".".repeat(10) + "RRRR.RRRRRR" + ".".repeat(9) + "#"
	made = _parse(rows)
	ok = _check("one solid rectangle" in String((made[1] as Array)[0]) if not (made[1] as Array).is_empty() else false, "a gap in the bar is refused") and ok
	made = _parse(_rows(8, 5))
	ok = _check(not (made[1] as Array).is_empty() and "sweeps" in String(made[1][0]), "a wall in its sweep is refused (%s)" % [made[1]]) and ok
	made = _parse(_rows(2))
	ok = _check(not (made[1] as Array).is_empty(), "a bar that sweeps through the ceiling is refused") and ok
	made = _parse(_rows(8), "legend:\n  R = spinner id=sp period=0\n---\n")
	ok = _check(not (made[1] as Array).is_empty(), "a period of 0 is refused") and ok
	made = _parse(_rows(8), "legend:\n  R = spinner id=sp period=4 spikes=sides\n---\n")
	ok = _check(not (made[1] as Array).is_empty(), "an unknown part in spikes= is refused") and ok
	return ok


func _path() -> bool:
	var ok := true
	var path := SpinnerPath.new("s", Rect2i(10, 8, 11, 2), 4.0, false, PackedStringArray(["bottom", "top_left"]))
	ok = _check(path.period() == 240, "four seconds is 240 ticks") and ok
	var same := true
	for body in path.body_count():
		same = same and path.rect_at(0, body) == path.rect_at(240, body)
	ok = _check(same, "a whole turn puts every block back") and ok
	# Block 0 is the top-left cell, 50 px left of the pivot and 5 above it.
	var at0 := path.rect_at(0, 0)
	ok = _check(at0.position == Vector2(100, 80), "block 0 starts where it is drawn (%s)" % at0.position) and ok
	var quarter := path.rect_at(60, 0)
	# Counter-clockwise a quarter turn takes the left end down: (-50, -5) -> (-5, +50).
	ok = _check(quarter.get_center() == path.pivot + Vector2(-5, 50), "a quarter turn counter-clockwise takes the left end down (%s)" % quarter.get_center()) and ok
	var half := path.rect_at(120, 0)
	ok = _check(half.get_center() == path.pivot + Vector2(50, 5), "a half turn swaps the ends (%s)" % half.get_center()) and ok
	var cw := SpinnerPath.new("c", Rect2i(10, 8, 11, 2), 4.0, true, PackedStringArray())
	ok = _check(cw.rect_at(60, 0).get_center() == cw.pivot + Vector2(5, -50), "clockwise takes it up the other way (%s)" % cw.rect_at(60, 0).get_center()) and ok
	var always := true
	for tick in range(0, 240, 7):
		for body in path.body_count():
			var r := path.rect_at(tick, body)
			always = always and r.position == r.position.round() and r.size == Vector2(10, 10)
	ok = _check(always, "every block is a 10 px square on a whole pixel at every tick") and ok
	ok = _check(path.radius > 58.0 and path.radius < 59.0 and path.sweeps(Vector2i(10, 8)) and not path.sweeps(Vector2i(3, 3)), "its sweep encloses centres, axis-aligned corners and snapping (%.1f)" % path.radius) and ok
	return ok


func _sim() -> bool:
	var ok := true
	var cfg: MovementConfig = load("res://src/player/movement.tres")
	var path := SpinnerPath.new("s", Rect2i(10, 8, 11, 2), 4.0, false, PackedStringArray(["bottom", "top_left"]))
	var movers := Movers.new([path])
	var none: Array = []
	ok = _check(movers.rects(0).size() == 22 - 16 and movers.hazard_rects(0).size() == 16, "6 safe blocks hold up, 16 spiked kill") and ok
	# Standing on the safe top-right: block at column 6..10 of the top row.
	var safe := movers.rects(0)[0]
	var s := MovementSim.State.new()
	s.position = Vector2(safe.get_center().x, safe.position.y - 5.0)
	s.grounded = true
	s.riding = -1
	MovementSim.step(cfg, s, none, 0.0, false, false, DT, movers, 0)
	ok = _check(s.grounded and s.riding >= 0 and not s.crushed, "a body on the safe half stands and is carried") and ok
	# A body inside a spiked block dies.
	var dead := MovementSim.State.new()
	var spike := movers.hazard_rects(0)[0]
	dead.position = spike.get_center()
	MovementSim.step(cfg, dead, none, 0.0, false, false, DT, movers, 0)
	ok = _check(dead.crushed, "touching a spiked block kills") and ok
	return ok


func _sweep_coverage() -> bool:
	var ok := true
	for size in [Vector2i(11, 2), Vector2i(10, 3), Vector2i(2, 10), Vector2i(1, 1), Vector2i(4, 4)]:
		for clockwise in [false, true]:
			for seconds in [0.05, 1.0, 8.0, 8.05]:
				for spikes in [PackedStringArray(), PackedStringArray(["all"]), PackedStringArray(["bottom", "top_left"])]:
					var path := SpinnerPath.new("coverage", Rect2i(Vector2i(11, 8), size), seconds, clockwise, spikes)
					for tick in path.period():
						for body in path.body_count():
							var rect := path.rect_at(tick, body)
							if rect.position != rect.position.round():
								return _check(false, "runtime stays on whole pixels")
							var first := Vector2i((rect.position / Grid.CELL).floor())
							var end := Vector2i((rect.end / Grid.CELL).ceil())
							for y in range(first.y, end.y):
								for x in range(first.x, end.x):
									var cell := Vector2i(x, y)
									if not path.swept_cells().has_point(cell) or not path.sweeps(cell) or not path.keep_out().encloses(rect):
										return _check(false, "sweep missed %s tick %d body %d size %s" % [cell, tick, body, size])
	ok = _check(true, "every runtime AABB cell is in sweeps, swept_cells and keep_out across dimensions, directions, hazards and periods") and ok
	var reproduced := SpinnerPath.new("regression", Rect2i(11, 8, 11, 2), 8.0, true, PackedStringArray())
	var obstacle := Grid.cell_rect(Rect2i(18, 3, 1, 1))
	ok = _check(reproduced.rect_at(395, 10).intersects(obstacle) and reproduced.sweeps(Vector2i(18, 3)), "tick 395/body 10 intersects declared cell (18,3)") and ok
	return ok


func _clearance() -> bool:
	var rows := _rows(8)
	rows[3][18] = "#"
	var made := _parse(rows, "legend:\n  R = spinner id=sp period=8 dir=cw\n---\n")
	var ok := _check("sweeps cell 18,3" in str(made[1]), "runtime-overlapping cell (18,3) is rejected by parser")
	rows = _rows(8)
	rows[14][19] = "#"
	made = _parse(rows, "legend:\n  R = spinner id=sp period=0.05\n---\n")
	ok = _check("sweeps cell 19,14" in str(made[1]), "the previously missed runtime corner cell is rejected by parser") and ok
	# The glyph is outside the sweep, but its upper-left machine corner is not.
	rows = _rows(8)
	rows[8][23] = "M"
	made = _parse(rows, LEGEND.replace("---", "  M = machine id=m upgrade=imprint\n---"))
	ok = _check("machine m is in the way of spinner" in str(made[1]), "the full 3TM footprint is checked, including cells away from its glyph (%s)" % [made[1]]) and ok
	# The save's extra landing-zone column, beyond its physical 3x3 body.
	rows = _rows(8)
	rows[8][24] = "S"
	made = _parse(rows, LEGEND.replace("---", "  S = save id=s\n---"))
	ok = _check("save s is in the way of spinner" in str(made[1]), "the full save zone is checked (%s)" % [made[1]]) and ok
	var info: RoomInfo = _parse(_rows(8))[0]
	var track := PlatformPath.new("rider", Rect2i(22, 15, 1, 1), Vector2i.UP, 6, 40.0, 0.0)
	info.movers.append(track)
	info.platforms.append(track)
	var errors: Array[String] = []
	RoomParser._check_platforms(info, errors)
	ok = _check("track or rider space" in str(errors), "spinner checks the entire tracked mover trip and its rider band") and ok
	info = _parse(_rows(8))[0]
	info.spinners.append(SpinnerPath.new("other", Rect2i(22, 8, 1, 1), 4.0, false, PackedStringArray()))
	errors.clear()
	RoomParser._check_platforms(info, errors)
	ok = _check("overlaps the sweep" in str(errors), "other spinner sweeps are checked even with separated glyphs") and ok
	return ok
