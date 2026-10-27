extends SceneTree

## Double jump in MovementSim: one extra jump in mid-air, refilled on landing,
## as strong as a ground jump, and never taking the place of a ground or coyote
## jump. Drives the simulation directly on a flat floor.

const DT := 1.0 / 60.0
const FLOOR_Y := 100.0

var _cfg: MovementConfig
var _floor: Array = [Rect2(0, FLOOR_Y, 400, 20)]
## Set by _tick: whether any tick since _stand made an air jump, and the
## highest the body's centre has been (smallest y).
var _air_seen := false
var _top := 0.0


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	var ok := true

	# Without the ability, a press in the air does nothing.
	var single := _stand(0)
	_jump_then_press(single, 20, true, true)
	ok = _check(not _air_seen, "no air jump with air_jumps = 0") and ok
	var single_rise := FLOOR_Y - 5.0 - _top

	# With one, a press at the top rises about as far again as the first jump.
	var double := _stand(1)
	_jump_then_press(double, 20, true, true)
	ok = _check(_air_seen, "an air jump happens with air_jumps = 1") and ok
	var double_rise := FLOOR_Y - 5.0 - _top
	ok = _check(double_rise > single_rise * 1.9 and double_rise < single_rise * 2.1, "an air jump at the top rises about as far again (%.1f px, a single jump %.1f)" % [double_rise, single_rise]) and ok

	# Letting go at once cuts the second jump short.
	var tapped := _stand(1)
	_jump_then_press(tapped, 20, false, true)
	ok = _check(FLOOR_Y - 5.0 - _top < double_rise - 5.0, "a tap on the second jump rises less than a hold (%.1f px)" % (FLOOR_Y - 5.0 - _top)) and ok

	# A third press does nothing; landing refills.
	var t := _stand(1)
	_jump_then_press(t, 20, true, false)
	ok = _check(t.air_left == 0 and not t.grounded, "the air jump is spent, and the body is still in the air") and ok
	_air_seen = false
	_tick(t, true, true)
	ok = _check(not _air_seen, "a press with none left does nothing") and ok
	for i in 300:
		_tick(t, false, false)
	ok = _check(t.grounded and t.air_left == 1, "landing refills the air jump") and ok

	# A press just after walking off a ledge is a ground (coyote) jump.
	var edge: Array = [Rect2(0, FLOOR_Y, 300, 20)]
	var c := MovementSim.State.new()
	c.position = Vector2(290.0, FLOOR_Y - 5.0)
	c.grounded = true
	c.air_jumps = 1
	c.air_left = 1
	for i in 60:
		MovementSim.step(_cfg, c, edge, 1.0, false, false, DT)
		if not c.grounded:
			break
	ok = _check(not c.grounded, "the body walked off the ledge") and ok
	MovementSim.step(_cfg, c, edge, 1.0, true, true, DT)
	ok = _check(c.jumped and not c.air_jumped and c.air_left == 1, "a coyote press is a ground jump and keeps the air jump") and ok

	# Past coyote time, the same press is the air jump.
	var late := MovementSim.State.new()
	late.position = Vector2(310.0, FLOOR_Y - 5.0)
	late.air_jumps = 1
	late.air_left = 1
	MovementSim.step(_cfg, late, edge, 1.0, true, true, DT)
	ok = _check(late.air_jumped and late.air_left == 0, "a press in the air, with no coyote time left, is the air jump") and ok

	# With none left, a press just before landing still buffers a ground jump.
	var b := _stand(1)
	_jump_then_press(b, 20, true, false)
	var landed := false
	var rebounded := false
	for i in 300:
		var near := not b.grounded and b.velocity.y > 0.0 and b.position.y > FLOOR_Y - 5.0 - 6.0
		MovementSim.step(_cfg, b, _floor, 0.0, near and not landed, true, DT)
		landed = landed or b.grounded
		if landed and b.jumped:
			rebounded = true
			break
	ok = _check(rebounded, "a press just before landing, with no air jump left, jumps on landing") and ok

	# Abilities: stored, saved and described.
	var abilities := Abilities.new()
	ok = _check(abilities.air_jumps == 0 and abilities.apply(Upgrades.get_def("double_jump"), 1) and abilities.air_jumps == 1, "the double_jump upgrade sets air_jumps to 1") and ok
	ok = _check(not abilities.apply(Upgrades.get_def("double_jump"), 1), "taking it again changes nothing") and ok
	ok = _check(Abilities.from_dict(abilities.to_dict()).air_jumps == 1 and Abilities.from_dict({}).air_jumps == 0, "air_jumps round-trips, and an old save loads as 0") and ok

	if ok:
		print("double jump test passed")
	quit(0 if ok else 1)


func _stand(air_jumps: int) -> MovementSim.State:
	var s := MovementSim.State.new()
	s.position = Vector2(100.0, FLOOR_Y - 5.0)
	s.grounded = true
	s.air_jumps = air_jumps
	s.air_left = air_jumps
	s.coyote = _cfg.coyote_time
	_air_seen = false
	_top = s.position.y
	return s


func _tick(s: MovementSim.State, press: bool, hold: bool) -> void:
	MovementSim.step(_cfg, s, _floor, 0.0, press, hold, DT)
	_air_seen = _air_seen or s.air_jumped
	_top = minf(_top, s.position.y)


## Jumps off the floor, waits `wait` ticks holding, then presses jump once more
## (held, or released at once). With `settle` the body then plays on until it
## has landed; without, it is left just after the second jump.
func _jump_then_press(s: MovementSim.State, wait: int, hold_second: bool, settle: bool) -> void:
	_tick(s, true, true)
	for i in wait:
		_tick(s, false, true)
	_tick(s, true, hold_second)
	if not settle:
		return
	for i in 300:
		_tick(s, false, hold_second)
		if s.grounded:
			break


func _check(ok: bool, what: String) -> bool:
	print(("  ok  " if ok else "  FAIL ") + what)
	return ok
