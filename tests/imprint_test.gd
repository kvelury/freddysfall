extends SceneTree

## Where an Imprint platform may go, and whether the player can land on one.
## Rooms are built from strings, so every rule is checked on its own.

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	var ok := true
	ok = _rules() and ok
	ok = _reach() and ok
	ok = _platform() and ok
	print("IMPRINT %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _rules() -> bool:
	var ok := true
	var marks := {Vector2i(2, 16): "P", Vector2i(31, 15): "X", Vector2i(31, 16): "X", Vector2i(20, 12): "~"}
	for x in range(10, 14):
		marks[Vector2i(x, 16)] = "^"
	var errors: Array[String] = []
	var built := RoomParser.build([
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": _room(marks)},
		{"id": "2", "grid_pos": Vector2i(1, 0), "text": _room({Vector2i(0, 15): "X", Vector2i(0, 16): "X", Vector2i(2, 16): "P"})},
	], "1", errors)
	ok = _check(errors.is_empty(), "the test rooms load %s" % [errors]) and ok
	var info: RoomInfo = built["rooms"]["1"]
	var nobody := Rect2(-100, -100, 10, 10)

	ok = _expect(info, Vector2i(5, 10), nobody, "", "open air is fine") and ok
	ok = _expect(info, Vector2i(-1, 5), nobody, "outside", "past the left edge") and ok
	ok = _expect(info, Vector2i(31, 5), nobody, "outside", "a platform that runs past the right edge") and ok
	ok = _expect(info, Vector2i(5, -1), nobody, "outside", "above the room") and ok
	ok = _expect(info, Vector2i(5, 17), nobody, "solid", "in the floor") and ok
	ok = _expect(info, Vector2i(0, 5), nobody, "solid", "in the wall") and ok
	ok = _expect(info, Vector2i(10, 16), nobody, "spikes", "on the spikes") and ok
	ok = _expect(info, Vector2i(9, 16), nobody, "spikes", "half on the spikes") and ok
	ok = _expect(info, Vector2i(10, 15), nobody, "", "just above the spikes, the core puzzle") and ok
	ok = _expect(info, Vector2i(10, 14), nobody, "", "higher above the spikes") and ok
	ok = _expect(info, Vector2i(20, 12), nobody, "no_imprint", "on a ~ cell") and ok
	ok = _expect(info, Vector2i(19, 12), nobody, "no_imprint", "with one end on a ~ cell") and ok
	ok = _expect(info, Vector2i(21, 12), nobody, "", "next to a ~ cell") and ok
	ok = _expect(info, Vector2i(29, 15), nobody, "door", "in the doorway") and ok
	ok = _expect(info, Vector2i(28, 15), nobody, "door", "within a cell of the door") and ok
	ok = _expect(info, Vector2i(27, 15), nobody, "", "two cells from the door") and ok
	ok = _expect(info, Vector2i(28, 13), nobody, "", "above the door") and ok
	var body := Rect2(100, 100, 10, 10)
	ok = _expect(info, Vector2i(10, 10), body, "player", "on the player") and ok
	ok = _expect(info, Vector2i(9, 10), body, "player", "half on the player") and ok
	ok = _expect(info, Vector2i(11, 10), body, "", "touching the player's side") and ok
	ok = _expect(info, Vector2i(10, 11), body, "", "touching the player's feet") and ok
	var others: Array[Rect2] = [Rect2(50, 50, 20, 10)]
	ok = _check(ImprintRules.check(info, Vector2i(6, 5), 2, nobody, others) == "imprint", "on another platform") and ok
	ok = _check(ImprintRules.check(info, Vector2i(6, 5), 2, nobody, []) == "", "the same place once the other is gone") and ok
	ok = _check(ImprintRules.check(info, Vector2i(5, 10), 5, nobody) == "", "a wider platform fits too") and ok
	ok = _check(ImprintRules.check(info, Vector2i(28, 10), 5, nobody) == "outside", "and runs out of room sooner") and ok
	return ok


func _reach() -> bool:
	var ok := true
	var info := RoomParser.parse_room("1", Vector2i.ZERO, _room({}), [] as Array[String])
	info.solids = RoomParser.merge_solids(info.rows)
	var rects: Array[Rect2] = []
	for rect in info.solids:
		rects.append(Grid.cell_rect(rect))
	ok = _check(MovementSim.standing(Grid.cell_center(Vector2i(5, 16)), rects), "the test room has a floor to stand on") and ok
	var stand := Grid.cell_center(Vector2i(5, 16))
	ok = _reaches(rects, Vector2i(6, 13), stand, Vector2.ZERO, true, true, "a platform 3 cells up and just beside the player (up, then steer)") and ok
	ok = _reaches(rects, Vector2i(9, 13), stand, Vector2.ZERO, true, true, "a platform 3 cells up and 4 along") and ok
	ok = _reaches(rects, Vector2i(6, 10), stand, Vector2.ZERO, true, false, "a platform 6 cells up is out of a jump's reach") and ok
	ok = _reaches(rects, Vector2i(5, 8), stand, Vector2.ZERO, true, false, "a platform far above") and ok
	ok = _reaches(rects, Vector2i(24, 13), stand, Vector2.ZERO, true, false, "a platform 19 cells away") and ok
	# In the air: falling past a platform, or rising to it.
	var air := Grid.cell_center(Vector2i(5, 8))
	ok = _reaches(rects, Vector2i(5, 12), air, Vector2.ZERO, false, true, "a platform below a falling player") and ok
	ok = _reaches(rects, Vector2i(5, 6), air, Vector2.ZERO, false, false, "a platform above a player who is not rising") and ok
	ok = _reaches(rects, Vector2i(6, 6), air, Vector2(0.0, -200.0), false, false, "a platform too high for a player who is rising slowly") and ok
	ok = _reaches(rects, Vector2i(6, 6), air, Vector2(0.0, -300.0), false, true, "a platform beside the top of a fast rise") and ok
	return ok


func _platform() -> bool:
	var ok := true
	var p := ImprintPlatform.new(Rect2(0, 0, 20, 10), 4.0)
	p.age = 1.0
	ok = _check(not p.blinked_off() and not p.expired(), "a new platform is solid and drawn") and ok
	p.age = 3.05
	ok = _check(not p.blinked_off(), "it is still drawn at the start of the last second") and ok
	p.age = 3.15
	ok = _check(p.blinked_off() and not p.expired(), "it blinks off in the last second") and ok
	p.age = 3.25
	ok = _check(not p.blinked_off(), "and back on") and ok
	p.age = 4.0
	ok = _check(p.expired(), "it is gone at its lifetime") and ok
	return ok


func _reaches(rects: Array[Rect2], cell: Vector2i, from: Vector2, velocity: Vector2, grounded: bool, expected: bool, label: String) -> bool:
	var platform := Grid.cell_rect(Rect2i(cell, Vector2i(2, 1)))
	var got := ImprintReach.can_land_on(_cfg, rects, platform, from, velocity, grounded)
	return _check(got == expected, "%s: %s" % [label, "reachable" if got else "not reachable"])


func _expect(info: RoomInfo, cell: Vector2i, body: Rect2, reason: String, label: String) -> bool:
	var got := ImprintRules.check(info, cell, 2, body)
	return _check(got == reason, "%s: %s (%s)" % [label, "legal" if reason.is_empty() else "refused as " + reason, got if got != reason else "ok"])


## One screen, walled, with `marks` (cell -> glyph) drawn in.
func _room(marks: Dictionary) -> String:
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += marks.get(Vector2i(x, y), "#" if edge else ".")
		rows.append(row)
	return "\n".join(rows) + "\n"


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
