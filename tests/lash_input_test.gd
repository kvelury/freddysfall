extends TestCase

## How lenient the lash key is, so jump, climb and lash can be chained fast
## (tests/fixtures/worlds/climb). A press that comes while the tongue is out,
## coming back, cooling down or hanging is kept for `TongueLash.LASH_BUFFER` and
## made as soon as it may, with look-up held at the press or at the moment it
## is made; a press kept longer than that is dropped, and so is one when the
## player is not in control. A sideways lash turns to go up if look-up comes
## within `TongueLash.UP_GRACE` (3 ticks), while the tip is still going out and
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
	ok = await _stale(world, player, tongue) and ok
	finish("LASH INPUT", ok)


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
	await ticks(3)
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
	for late in [1, 2, 3, 4]:
		_put(world)
		await _press(tongue)
		ok = check(tongue.active and not tongue.up and tongue.phase == OUT, "lash with no look-up goes sideways") and ok
		for i in late - 1:
			await physics_frame
		tongue.scripted_up = true
		await physics_frame
		tongue.scripted_up = false
		var above: bool = tongue.tip().y < player.global_position.y - 4.0 and is_equal_approx(tongue.tip().x, player.global_position.x)
		if late <= 3:
			ok = check(tongue.up and above and player.lashing_up, "look-up %d tick(s) after the lash sends it up" % late) and ok
		else:
			ok = check(not tongue.up and not player.lashing_up, "look-up 4 ticks after it leaves it sideways") and ok
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
