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
	ok = _check(path.radius > 55.0 and path.radius < 57.0 and path.sweeps(Vector2i(10, 8)) and not path.sweeps(Vector2i(3, 3)), "its sweep is the circle the corners make (%.1f)" % path.radius) and ok
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
