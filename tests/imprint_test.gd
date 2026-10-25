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
	ok = _countdown() and ok
	ok = _shrink() and ok
	ok = _lockout() and ok
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


## Classic only: the blink on the last dash.
func _platform() -> bool:
	var ok := true
	var p := ImprintPlatform.new(Rect2(0, 0, 20, 10), 4.0, false)
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


## Ages a platform the way the tool does, one tick at a time up to `age`, and
## returns the blocks that went on the way.
func _age_to(p: ImprintPlatform, age: float) -> Array[Rect2]:
	var gone: Array[Rect2] = []
	while p.age < age - 0.0001:
		p.age = minf(p.age + 1.0 / 60.0, age)
		gone.append_array(p.update_footing())
	return gone


## The platform is its own clock: one block goes in each equal share of its life,
## from the ends toward the middle, left first. The one that lasts is cells / 2.
func _shrink() -> bool:
	var ok := true
	var p := ImprintPlatform.new(Rect2(100, 50, 30, 10), 1.5)
	ok = _check(p.shrinks and p.cells == 3 and p.rect == p.full_rect, "a new platform of three cells is whole and shrinks") and ok
	_age_to(p, 0.25)
	ok = _check(p.rect == Rect2(100, 50, 30, 10) and p.blocks_left() == 3, "it is whole at 0.25 s") and ok
	var gone := _age_to(p, 0.75)
	ok = _check(is_equal_approx(p.rect.position.x, 110.0) and is_equal_approx(p.rect.size.x, 20.0) and p.blocks_left() == 2, "at 0.75 s the left block has gone (%s)" % [p.rect]) and ok
	ok = _check(gone == [Rect2(100, 50, 10, 10)], "and update_footing said which (%s)" % [gone]) and ok
	gone.append_array(_age_to(p, 1.25))
	ok = _check(is_equal_approx(p.rect.position.x, 110.0) and is_equal_approx(p.rect.size.x, 10.0) and p.blocks_left() == 1, "at 1.25 s only the middle block stands (%s)" % [p.rect]) and ok
	ok = _check(gone == [Rect2(100, 50, 10, 10), Rect2(120, 50, 10, 10)], "the right block went second (%s)" % [gone]) and ok
	ok = _check(_age_to(p, 1.49).is_empty() and p.rect.size.x == 10.0 and not p.expired(), "the last block stays until the end, and is never reported as gone") and ok
	_age_to(p, 1.5)
	ok = _check(p.expired() and p.blocks_left() == 0, "the platform is gone at 1.5 s") and ok
	ok = _check(p.update_footing().is_empty(), "and update_footing has nothing more to give") and ok

	var counts := []
	var q := ImprintPlatform.new(Rect2(0, 0, 30, 10), 1.5)
	for age in [0.25, 0.75, 1.25]:
		q.age = age
		counts.append(q.blocks_left())
	ok = _check(counts == [3, 2, 1], "blocks_left at 0.25, 0.75 and 1.25 s is 3, 2, 1 (%s)" % [counts]) and ok

	# The order, from the ends toward the middle: the block left standing is cells / 2.
	for width in [1, 2, 3, 4, 5]:
		var w := ImprintPlatform.new(Rect2(100, 0, 10 * width, 10), 1.5)
		_age_to(w, 1.49)
		var want := 100.0 + 10.0 * float(width / 2)
		ok = _check(w.rect == Rect2(want, 0, 10, 10), "width %d ends on block %d (%s)" % [width, width / 2, w.rect]) and ok
	var five := ImprintPlatform.new(Rect2(0, 0, 50, 10), 1.5)
	var order := []
	for i in range(1, 151):
		five.age = 0.01 * float(i)
		for block in five.update_footing():
			order.append(int(block.position.x / 10.0))
	ok = _check(order == [0, 4, 1, 3], "width 5 loses 0, 4, 1, 3 and keeps 2 (%s)" % [order]) and ok

	var one := ImprintPlatform.new(Rect2(100, 50, 10, 10), 1.5)
	var changed := false
	for i in range(1, 150):
		one.age = 0.01 * float(i)
		one.update_footing()
		changed = changed or one.rect != Rect2(100, 50, 10, 10)
	ok = _check(not changed, "a width of one never changes before it expires") and ok

	# The warning: only the block that goes next blinks, in its last 0.25 s.
	var b := ImprintPlatform.new(Rect2(100, 50, 30, 10), 1.5)
	var early := false
	for age in [0.1, 0.15, 0.2]:
		b.age = age
		early = early or b.blinking_off()
	ok = _check(not early, "nothing blinks while a block is far from going") and ok
	b.age = 0.0
	ok = _check(b.next_cell() == 0 and is_equal_approx(b.time_to_next(), 0.5), "the left block goes first, in 0.5 s") and ok
	var blinked := false
	for age in [0.26, 0.28, 0.3, 0.32, 0.34, 0.36, 0.38]:
		b.age = age
		blinked = blinked or b.blinking_off()
	ok = _check(blinked, "the next block blinks off at some time in its last 0.25 s") and ok
	b.age = 0.35
	ok = _check(b.blinking_off() and b.rect == Rect2(100, 50, 30, 10), "while it blinks it still counts as footing") and ok
	ok = _check(b.drawn_rect() == Rect2(110, 50, 20, 10), "and the left block is left out of the drawing (%s)" % [b.drawn_rect()]) and ok
	b.age = 0.55
	b.update_footing()
	b.age = 0.95
	ok = _check(b.next_cell() == 2 and b.blinking_off() and b.drawn_rect() == Rect2(110, 50, 10, 10), "the right block is next, and it is the one left out (%s)" % [b.drawn_rect()]) and ok
	b.age = 1.0
	b.update_footing()
	b.age = 1.35
	ok = _check(b.next_cell() == 1 and b.blinking_off(), "the last block blinks before it goes with the platform") and ok
	ok = _check(b.drawn_rect().size.x <= 0.0, "and nothing is drawn while it is blinked off") and ok
	var quick := ImprintPlatform.new(Rect2(0, 0, 30, 10), 0.3)
	ok = _check(is_equal_approx(quick.warn_time(), 0.05), "the warning is no more than half a share (%.3f)" % quick.warn_time()) and ok
	ok = _check(is_equal_approx(b.warn_time(), 0.25), "and 0.25 s at the starting life") and ok

	# Classic keeps its width and has no blink of this kind.
	var classic := ImprintPlatform.new(Rect2(100, 50, 30, 10), 1.5, false)
	var same := true
	var blink := false
	for i in range(1, 150):
		classic.age = 0.01 * float(i)
		same = same and classic.update_footing().is_empty() and classic.rect == classic.full_rect
		blink = blink or classic.blinking_off()
	ok = _check(same and not classic.shrinks, "a Classic platform keeps its width for its whole life") and ok
	ok = _check(not blink and classic.next_cell() == -1 and classic.blocks_left() == 3, "and no block blinks") and ok
	return ok


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond


## Classic only: the dashes are a clock. One goes each quarter of the platform's
## life, from the left, and the last one is the one that blinks.
func _countdown() -> bool:
	var ok := true
	var p := ImprintPlatform.new(Rect2(100, 50, 20, 10), 4.0, false)
	var full := p.line_rects()
	ok = _check(full.size() == 4 and p.lines_left() == 4, "a new platform of two cells has four lines (%d)" % full.size()) and ok
	var counts := []
	for age in [0.5, 1.5, 2.5, 3.5]:
		p.age = age
		counts.append(p.lines_left())
	ok = _check(counts == [4, 3, 2, 1], "a line goes each second: 4, 3, 2, 1 (%s)" % [counts]) and ok
	p.age = 1.5
	var rest := p.line_rects()
	ok = _check(rest.size() == 3 and rest[0] == full[1] and rest[2] == full[3], "the leftmost goes first, and the rest stay where they were") and ok
	p.age = 3.5
	ok = _check(p.line_rects() == [full[3]], "the last line is the rightmost") and ok
	p.age = 3.999
	ok = _check(p.lines_left() == 1, "one line is left until the very end") and ok
	p.age = 4.0
	ok = _check(p.lines_left() == 0 and p.expired(), "none at the end") and ok
	var wide := ImprintPlatform.new(Rect2(0, 0, 30, 10), 6.0, false)
	var shown := []
	for age in [0.5, 2.5, 5.5]:
		wide.age = age
		shown.append(wide.lines_left())
	ok = _check(shown == [7, 5, 1], "a wider platform with a longer life counts down evenly (%s)" % [shown]) and ok

	# The starting platform: 1.5 seconds and four lines, so one goes every
	# 0.375 s, and it blinks while the last one is alone (from 1.125 s).
	var start := ImprintPlatform.new(Rect2(0, 0, 20, 10), Abilities.new().imprint_duration, false)
	ok = _check(is_equal_approx(start.lifetime, 1.5), "a starting platform lasts 1.5 seconds") and ok
	var quarters := []
	for age in [0.2, 0.5, 0.9, 1.2]:
		start.age = age
		quarters.append(start.lines_left())
	ok = _check(quarters == [4, 3, 2, 1], "its four lines go one every 0.375 s: 4, 3, 2, 1 (%s)" % [quarters]) and ok
	ok = _check(is_equal_approx(start.blink_time(), 0.375), "it blinks for the last line's share, 0.375 s (%.3f)" % start.blink_time()) and ok
	var early := false
	for i in 11:
		start.age = 0.1 * float(i) + 0.05
		early = early or start.blinked_off()
	ok = _check(not early, "it does not blink while two or more lines are left") and ok
	start.age = 1.15
	ok = _check(start.lines_left() == 1 and start.blinked_off() and not start.expired(), "it blinks once only the last line is left") and ok
	start.age = 1.25
	ok = _check(not start.blinked_off(), "and comes back on between blinks") and ok
	start.age = 1.5
	ok = _check(start.expired() and start.lines_left() == 0, "and is gone at 1.5 seconds") and ok
	return ok


## A click never replaces a platform: it is refused while the limit's worth
## stand, and while the cooldown after one breaks is running.
func _lockout() -> bool:
	var ok := true
	ok = _check(ImprintRules.blocked(0, 1, 0.0).is_empty(), "with none standing and no cooldown, a platform may go") and ok
	ok = _check(ImprintRules.blocked(1, 1, 0.0) == "limit", "one standing at a limit of one: refused as limit") and ok
	ok = _check(ImprintRules.blocked(0, 1, 0.2) == "cooldown", "none standing but a cooldown running: refused as cooldown") and ok
	ok = _check(ImprintRules.blocked(1, 1, 0.2) == "limit", "the limit is reported before the cooldown") and ok
	ok = _check(ImprintRules.blocked(1, 2, 0.0).is_empty(), "one standing at a limit of two: a second may go") and ok
	ok = _check(ImprintRules.blocked(2, 2, 0.0) == "limit", "two standing at a limit of two: refused as limit") and ok
	ok = _check(ImprintRules.blocked(1, 0, 0.0) == "limit" and ImprintRules.blocked(0, 0, 0.0).is_empty(), "a limit of zero is treated as one") and ok
	return ok
