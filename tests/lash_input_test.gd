extends TestCase

## How lenient the lash key is, so jump, climb and lash can be chained fast
## (tests/fixtures/worlds/climb). A press that comes while the tongue is out,
## coming back, cooling down or hanging is kept for `TongueLash.LASH_BUFFER` and
## made as soon as it may, with look-up held at the press or at the moment it
## is made; a press kept longer than that is dropped, and so is one when the
## player is not in control. A sideways lash turns to go up if look-up comes
## within `TongueLash.UP_GRACE` (6 ticks), while the tip is still going out and
## has hit nothing. A jump off a Tongue Climb hang pulls the tongue in at once,
## so a lash pressed with or just before it goes after only the cooldown; a
## hang that runs out still lets the tongue ease back.

const FIXTURE := "res://tests/fixtures/worlds/climb/"
## TongueLash.Phase (the class is not named here: it reads the autoloads).
const OUT := 0
const BACK := 2


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var ok := true
	var state: Node = root.get_node("GameState")
	root.get_node("WorldData").load_from(FIXTURE + "world.json", FIXTURE + "rooms/")
	state.reset()
	var world: Node = await boot_world("1")
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	player.scripted = true
	tongue.scripted = true
	var ab: Abilities = state.abilities
	ab.tongue_unlocked = true
	ab.air_jumps = 1
	player.air_jumps = 1
	await until(func() -> bool: return not world.is_busy(), 120)
	await ticks(2)
	ok = check(is_equal_approx(tongue.LASH_BUFFER, player.config.jump_buffer), "the lash is kept as long as a jump is (%.2f s)" % tongue.LASH_BUFFER) and ok

	ok = await _buffer(world, player, tongue) and ok
	ok = await _late_up(world, player, tongue) and ok
	ok = await _climb_chain(world, player, tongue, ab) and ok
	ok = await _kept_hold(world, tongue, ab) and ok
	ok = await _stale(world, player, tongue) and ok
	ok = await _modal(world, tongue) and ok
	ok = await _fresh_press(world, tongue, ab) and ok
	ok = await _air_keys(world, player, tongue) and ok
	ok = await _readout(world, player, tongue) and ok
	finish("LASH INPUT", ok)


## A kept press remembers that it was held for `climb_press` even if X is let go
## before the lash is made; one let go too early stays a plain lash.
func _kept_hold(world: Node, tongue: Node, ab: Abilities) -> bool:
	var ok := true
	var was := ab.climb_press
	ab.climb_press = 0.05
	for c in [[4, true, "held for the hold and let go before the kept lash is made, it still climbs"], [1, false, "let go before the hold, the kept lash is a plain lash"]]:
		_put(world)
		tongue.scripted_held = false
		await _press(tongue)
		await until(func() -> bool: return tongue.phase == BACK, 60)
		await ticks(5)
		tongue.scripted_held = true
		await _press(tongue)
		await ticks(c[0] - 1)
		tongue.scripted_held = false
		var got := await until(func() -> bool: return tongue.active and tongue.phase == 0, 20)
		ok = check(got >= 0 and (tongue._intent == 2) == c[1], "a kept press " + c[2]) and ok
	ab.climb_press = was
	tongue.scripted_held = true
	return ok


## Facing left from the middle of the floor, a lash meets nothing.
func _put(world: Node, cell := Vector2i(15, 16), facing := -1) -> void:
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	tongue.clear()
	tongue.scripted_up = false
	player.scripted_x = 0.0
	player.scripted_jump_pressed = false
	player.place(world.current.position + Grid.cell_center(cell), world.current.world_rects())
	player.facing = facing


## Presses lash for one tick.
func _press(tongue: Node) -> void:
	tongue.scripted_lash = true
	await physics_frame


func _buffer(world: Node, player: Player, tongue: Node) -> bool:
	var ok := true
	# Before: a press in the cooldown was dropped. Now it goes when the wait is over.
	_put(world)
	await _press(tongue)
	ok = check(tongue.active, "a lash is made") and ok
	await until(func() -> bool: return not tongue.active, 60)
	ok = check(tongue.cooldown_left > 0.0, "then the wait") and ok
	await _press(tongue)
	ok = check(not tongue.active and tongue.buffer_left > 0.0, "a press in the wait is kept") and ok
	var got := await until(func() -> bool: return tongue.active, 10)
	ok = check(got >= 0 and got <= 3, "and made as soon as the wait is over (%d ticks)" % got) and ok

	# During the return, close enough to the end.
	_put(world)
	await _press(tongue)
	await until(func() -> bool: return tongue.phase == BACK, 60)
	await ticks(5)
	await _press(tongue)
	ok = check(tongue.active and tongue.buffer_left > 0.0, "a press while the tongue comes back is kept") and ok
	var ended := false
	got = -1
	for i in 15:
		await physics_frame
		ended = ended or not tongue.active
		if ended and tongue.active:
			got = i
			break
	ok = check(got >= 0, "and made once it is back and the wait is over (%d ticks)" % got) and ok

	# Too early: a press near the start of a full miss (18 ticks out and back, 3 to wait) is forgotten.
	_put(world)
	await _press(tongue)
	await physics_frame
	await _press(tongue)
	await until(func() -> bool: return not tongue.active, 60)
	got = await until(func() -> bool: return tongue.active, 15)
	ok = check(got == -1 and tongue.buffer_left == 0.0, "a press more than %.2f s early does nothing" % tongue.LASH_BUFFER) and ok

	# Look-up at the press is kept with it; look-up when it is made counts too.
	_put(world)
	await _press(tongue)
	await until(func() -> bool: return not tongue.active, 60)
	tongue.scripted_up = true
	await _press(tongue)
	tongue.scripted_up = false
	await until(func() -> bool: return tongue.active, 10)
	ok = check(tongue.active and tongue.up, "a kept press made with look-up held goes up, though the key is let go") and ok
	_put(world)
	await _press(tongue)
	await until(func() -> bool: return not tongue.active, 60)
	await _press(tongue)
	tongue.scripted_up = true
	await until(func() -> bool: return tongue.active, 10)
	ok = check(tongue.active and tongue.up, "a kept sideways press goes up if look-up is held when it is made") and ok
	tongue.scripted_up = false
	return ok


func _late_up(world: Node, player: Player, tongue: Node) -> bool:
	var ok := true
	for late in [1, 3, 6, 7]:
		_put(world)
		await _press(tongue)
		ok = check(tongue.active and not tongue.up and tongue.phase == OUT, "lash with no look-up goes sideways") and ok
		for i in late - 1:
			await physics_frame
		tongue.scripted_up = true
		await physics_frame
		tongue.scripted_up = false
		var above: bool = tongue.tip().y < player.global_position.y - 4.0 and is_equal_approx(tongue.tip().x, player.global_position.x)
		if late <= 6:
			ok = check(tongue.up and above and player.lashing_up, "look-up %d tick(s) after the lash sends it up" % late) and ok
		else:
			ok = check(not tongue.up and not player.lashing_up, "look-up 7 ticks after it leaves it sideways") and ok
	# A tip that has already hit something is not sent again.
	_put(world, Vector2i(19, 16), 1)
	await _press(tongue)
	ok = check(tongue.phase != OUT or not tongue.active, "pressed to the pillar, the lash hits at once") and ok
	tongue.scripted_up = true
	await physics_frame
	tongue.scripted_up = false
	ok = check(not tongue.up, "and look-up after it does not turn it") and ok
	return ok


func _climb_chain(world: Node, player: Player, tongue: Node, ab: Abilities) -> bool:
	var ok := true
	ab.tongue_climb = true
	# Wall: lash pressed (with look-up) the tick before the jump off.
	_put(world, Vector2i(17, 12), 1)
	await _press(tongue)
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0, "a lash at the pillar hangs him from it") and ok
	tongue.scripted_up = true
	await _press(tongue)
	ok = check(player.hanging() and tongue.buffer_left > 0.0, "a lash while hanging is kept") and ok
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(not player.climbing() and player.velocity.y < 0.0, "jump lets go of the wall") and ok
	ok = check(not tongue.active or tongue.up, "and the tongue is pulled in at once (phase %d)" % tongue.phase) and ok
	var got := await until(func() -> bool: return tongue.active and tongue.up, 6)
	ok = check(got >= 0, "the kept lash goes up within the wait (%d ticks)" % got) and ok
	tongue.scripted_up = false

	# Wall: lash and jump on the same tick.
	_put(world, Vector2i(17, 12), 1)
	await _press(tongue)
	await until(func() -> bool: return player.hanging(), 60)
	tongue.scripted_up = true
	player.scripted_jump_pressed = true
	await _press(tongue)
	tongue.scripted_up = false
	ok = check(not player.climbing() and not tongue.active, "a jump and a lash on one tick: off the wall, the tongue in") and ok
	got = await until(func() -> bool: return tongue.active and tongue.up, 6)
	ok = check(got >= 0, "and the lash goes up straight after the wait (%d ticks)" % got) and ok

	# Ceiling: the drop by jump pulls it in too.
	_put(world, Vector2i(7, 16), 1)
	tongue.scripted_up = true
	await _press(tongue)
	ok = check(await until(func() -> bool: return player.hanging() and player.climbing_ceiling(), 60) >= 0, "an up-lash hangs him from the slab") and ok
	player.scripted_jump_pressed = true
	await _press(tongue)
	ok = check(not player.climbing() and not tongue.active, "a jump and a lash under the slab: he drops, the tongue in") and ok
	got = await until(func() -> bool: return tongue.active and tongue.up, 6)
	ok = check(got >= 0, "and the lash goes up straight after the wait (%d ticks)" % got) and ok
	tongue.scripted_up = false

	# A hang that runs out still lets the tongue ease back.
	_put(world, Vector2i(17, 12), 1)
	await _press(tongue)
	await until(func() -> bool: return player.hanging(), 60)
	await until(func() -> bool: return not player.climbing(), 60)
	ok = check(tongue.active and tongue.phase == BACK, "when the hang runs out the tongue comes back as before") and ok
	ab.tongue_climb = false
	_put(world)
	return ok


func _stale(world: Node, player: Player, tongue: Node) -> bool:
	var ok := true
	# A kept press is forgotten when the player loses control.
	_put(world)
	await _press(tongue)
	await until(func() -> bool: return not tongue.active, 60)
	await _press(tongue)
	ok = check(tongue.buffer_left > 0.0, "a press in the wait is kept") and ok
	player.input_enabled = false
	await physics_frame
	ok = check(tongue.buffer_left == 0.0 and not tongue.active, "taking control away forgets it") and ok
	await ticks(4)
	player.input_enabled = true
	ok = check(await until(func() -> bool: return tongue.active, 10) == -1, "and nothing is lashed when control comes back") and ok
	# A press with no control is not kept.
	player.input_enabled = false
	await _press(tongue)
	ok = check(tongue.buffer_left == 0.0, "a press with no control is not kept") and ok
	player.input_enabled = true
	# Clearing the tongue (room change, death, warp, retry) forgets it too.
	_put(world)
	await _press(tongue)
	await _press(tongue)
	await until(func() -> bool: return not tongue.active, 60)
	tongue.clear()
	ok = check(tongue.buffer_left == 0.0, "clearing the tongue forgets a kept press") and ok
	return ok


## Lets go of every key the real-key cases press.
func _release_keys() -> void:
	for action in ["jump", "lash", "look_up", "move_left", "move_right"]:
		Input.action_release(action)


## The real keys, not the scripted stand-ins: jump, and in the air look-up and
## lash in any order a player presses them (steering too) lash up, and holding
## look-up in the air shows the up-lash picture before the lash is made.
func _air_keys(world: Node, player: Player, tongue: Node) -> bool:
	var ok := true
	player.scripted = false
	tongue.scripted = false
	# [label, ticks look-up is held before X (-1: one tick after), steering key]
	var cases := [["look-up held, then X", 5, ""], ["look-up and X on one tick", 0, ""], ["X, then look-up a tick later", -1, ""], ["steering right", 5, "move_right"], ["steering left", 5, "move_left"]]
	for c in cases:
		_put(world, Vector2i(12, 16), 1)
		_release_keys()
		await ticks(2)
		Input.action_press("jump")
		if c[2] != "":
			Input.action_press(c[2])
		await ticks(14)
		var air := not player.is_on_floor()
		if c[1] > 0:
			Input.action_press("look_up")
			await ticks(c[1])
			ok = check(player.animator.pose == PlayerAnimator.Pose.LASH_UP and not tongue.active, "%s: in the air, look-up shows the up-lash picture before the lash" % c[0]) and ok
		elif c[1] == 0:
			Input.action_press("look_up")
		Input.action_press("lash")
		await physics_frame
		if c[1] < 0:
			Input.action_press("look_up")
		await ticks(2)
		ok = check(air and tongue.active and tongue.up and player.animator.pose == PlayerAnimator.Pose.LASH_UP, "%s: in the air, the lash goes up (air %s, up %s)" % [c[0], air, tongue.up]) and ok
		_release_keys()
	player.scripted = true
	tongue.scripted = true
	_put(world)
	await ticks(2)
	return ok


## The dev tools' Show lash input says each press in the toast line, and only
## in a dev test.
func _readout(world: Node, player: Player, tongue: Node) -> bool:
	var ok := true
	var session: Node = root.get_node("DevSession")
	var mode: int = session.mode
	session.mode = session.Mode.NORMAL
	ok = check(not session.set_lash_log(world, true).is_empty() and not session.lash_log, "Show lash input is refused outside a dev test") and ok
	session.mode = session.Mode.DEV_TEST
	ok = check(session.set_lash_log(world, true).is_empty() and session.lash_log_active() and session.status_line().contains("lash input"), "and can be turned on in one, and the status line says so") and ok
	ok = check(not _has_key(root.get_node("GameState").to_dict(), "lash_log") and not _has_key(session.loadout, "lash_log"), "it is in no save or loadout") and ok
	_put(world)
	tongue.last_log = ""
	tongue.scripted_up = true
	await _press(tongue)
	ok = check(tongue.last_log.begins_with("Lash UP") and tongue.last_log.contains("look-up held: yes"), "a lash up is said (%s)" % tongue.last_log) and ok
	tongue.scripted_up = false
	await _press(tongue)
	ok = check(tongue.last_log.begins_with("Lash kept (tongue out)") and tongue.last_log.contains("look-up held: no"), "a kept press says why (%s)" % tongue.last_log) and ok
	await until(func() -> bool: return tongue.active and not tongue.up, 40)
	ok = check(tongue.last_log.begins_with("Kept lash made side") or tongue.last_log.begins_with("Kept lash ran out") or tongue.last_log.begins_with("Climb:") or tongue.last_log.begins_with("Lash only"), "and what came of it (%s)" % tongue.last_log) and ok
	player.input_enabled = false
	await _press(tongue)
	ok = check(tongue.last_log == "Lash dropped: not in control", "a press with no control is said to be dropped (%s)" % tongue.last_log) and ok
	player.input_enabled = true
	ok = check(session.set_lash_log(world, false).is_empty() and not session.lash_log_active(), "and it turns off") and ok
	tongue.last_log = ""
	_put(world)
	await _press(tongue)
	ok = check(tongue.last_log == "", "off, nothing is said") and ok
	session.mode = mode
	return ok


func _has_key(value: Variant, key: String) -> bool:
	if value is Dictionary:
		for k in value:
			if str(k) == key or _has_key(value[k], key):
				return true
	elif value is Array:
		for item in value:
			if _has_key(item, key):
				return true
	return false


## A kept press does not outlive a pause, the map, the dev panel or a popup:
## the tree is paused, so the tongue never sees the modal; `World.acquire_modal`
## drops it.
func _modal(world: Node, tongue: Node) -> bool:
	var ok := true
	for owner in ["pause", "map", "dev", "power"]:  # PauseMenu.OWNER, MapOverlay, DevPanel, PowerPopup.OWNER
		_put(world)
		await _press(tongue)
		await until(func() -> bool: return not tongue.active, 60)
		await _press(tongue)
		ok = check(tongue.buffer_left > 0.0, "%s: a press in the wait is kept" % owner) and ok
		ok = check(world.acquire_modal(owner), "%s: the modal is taken" % owner) and ok
		ok = check(tongue.buffer_left == 0.0, "%s: taking it forgets the kept press" % owner) and ok
		await ticks(3)
		world.release_modal(owner)
		var got := await until(func() -> bool: return tongue.active, 10)
		ok = check(got == -1, "%s: and nothing is lashed when it closes (%d)" % [owner, got]) and ok
	return ok


## A fresh press that lashes uses up a kept one, so it cannot lash again on
## its own: against a wall (a lash that hits at once is over in a tick) and
## with the fastest tongue the dev tools allow.
func _fresh_press(world: Node, tongue: Node, ab: Abilities) -> bool:
	var ok := true
	var speed := ab.tongue_speed
	for c in [["against the pillar", Vector2i(19, 16), 1, speed], ["fastest tongue", Vector2i(15, 16), -1, 2000.0]]:
		ab.tongue_speed = c[3]
		_put(world, c[1], c[2])
		await _press(tongue)
		await until(func() -> bool: return not tongue.active, 60)
		await _press(tongue)
		ok = check(not tongue.active and tongue.buffer_left > 0.0, "%s: a press in the wait is kept" % c[0]) and ok
		# Press again on the tick the wait ends: the last tick of the wait
		# leaves a hair of it, under a thousandth of a second.
		await until(func() -> bool: return tongue.cooldown_left < 0.001, 10)
		ok = check(tongue.buffer_left > 0.0 and not tongue.active, "%s: the kept press is still waiting" % c[0]) and ok
		await _press(tongue)
		ok = check(tongue.active and tongue.buffer_left == 0.0, "%s: a fresh press on the ready tick lashes and uses up the kept one (%.3f left)" % [c[0], tongue.buffer_left]) and ok
		await until(func() -> bool: return not tongue.active, 60)
		var again := await until(func() -> bool: return tongue.active, 15)
		ok = check(again == -1, "%s: and no second lash follows on its own (%d)" % [c[0], again]) and ok
	ab.tongue_speed = speed
	return ok
