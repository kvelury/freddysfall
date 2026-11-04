extends TestCase

## Tongue Climb. In a small room of its own (tests/fixtures/worlds/climb): a
## pillar whose left face is at x = 200, a breakable column at x = 260 and a slab
## whose underside is at y = 120. With the power-up off a lash is what it was.
## With it on, a lash that sticks pulls Freddy to the wall and he hangs there
## for the hold time, wiggling in the last part; he can jump off (a ground
## jump, with the double jump back), or drop from a ceiling; he can or cannot
## stick again at once as the toggle says; a breakable wall takes its hit and is
## stuck to only when the toggle says so and it still stands; an Imprint
## platform is never stuck to; and room changes, deaths and the busy world let go.

const FIXTURE := "res://tests/fixtures/worlds/climb/"
## Where Freddy hangs: the pillar's face, less half his body and the gap.
const HANG_X := 200.0 - 5.0 - MovementSim.CLIMB_GAP
const WALL := "cb1"
## TongueLash.Phase.CLIMB (the class is not named here: it reads the autoloads).
const CLIMB_PHASE := 3


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
	tongue.scripted = true
	var ab: Abilities = state.abilities
	ab.tongue_unlocked = true
	ab.air_jumps = 1
	player.air_jumps = 1
	ok = _defaults(ab) and ok

	# Power-up off: a lash at the pillar sticks the tip for a moment and comes back; Freddy stays put.
	_put(world, Vector2i(17, 12))
	tongue.lash()
	var saw := await _watch(player, tongue)
	ok = check(not saw["climbed"] and is_equal_approx(player.global_position.x, 175.0), "with the power-up off a lash pulls nothing (x %.1f)" % player.global_position.x) and ok

	# On: pulled to the wall, hung there with gravity off.
	ab.tongue_climb = true
	_put(world, Vector2i(17, 12))
	ok = check(tongue.lash(), "a lash is made") and ok
	var got := await until(func() -> bool: return player.hanging(), 60)
	ok = check(got >= 0 and tongue.phase == CLIMB_PHASE, "a lash that hits the pillar pulls him to it (%d ticks) and the tongue holds" % got) and ok
	ok = check(absf(player.global_position.x - HANG_X) < 0.01, "he hangs a gap short of the face, at x %.2f (expected %.2f)" % [player.global_position.x, HANG_X]) and ok
	var y0 := player.global_position.y
	var hung := 0
	var wiggles := 0
	var offsets_ok := true
	var steady := true
	for i in 70:
		if not player.hanging():
			break
		hung += 1
		if player.wiggling():
			wiggles += 1
		offsets_ok = offsets_ok and (absf(player.wiggle_offset().x) == 1.0) == player.wiggling()
		steady = steady and player.global_position.y == y0 and player.velocity == Vector2.ZERO
		await physics_frame
	ok = check(steady, "gravity is off while he hangs") and ok
	ok = check(absi(hung - 30) <= 1, "he hangs the hold time, 0.5 s (%d ticks)" % hung) and ok
	ok = check(absi(wiggles - 12) <= 1, "and wiggles for the last 0.2 s (%d ticks)" % wiggles) and ok
	ok = check(offsets_ok, "the wiggle is a 1 px shift only while he wiggles") and ok
	await physics_frame
	await physics_frame
	ok = check(not player.climbing() and player.velocity.y > 0.0, "when the time runs out he lets go and falls") and ok
	ok = check(await until(func() -> bool: return not tongue.active, 60) >= 0, "and the tongue goes back in") and ok

	# Jump off the wall: a ground jump steered by the keys, the air jump back, and he may stick again at once.
	ab.climb_land_to_restick = true
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	player.scripted_x = -1.0
	for i in 5:
		await physics_frame
	ok = check(player.facing == 1 and tongue.lash() == false, "stuck, he keeps facing the wall and a lash does nothing") and ok
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(not player.climbing() and is_equal_approx(player.velocity.y, -player.config.jump_speed), "jump while stuck is a ground jump (%.0f)" % player.velocity.y) and ok
	ok = check(player.velocity.x < 0.0, "steered by the keys") and ok
	player.scripted_x = 0.0
	for i in 6:
		await physics_frame
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(is_equal_approx(player.velocity.y, -player.config.air_jump_speed), "and the double jump is back (%.0f)" % player.velocity.y) and ok
	await until(func() -> bool: return not tongue.active and tongue.cooldown_left <= 0.0, 90)
	player.facing = 1
	tongue.lash()
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0, "after jumping off he sticks again with no landing, even with Land before re-stick on") and ok

	# Land before re-stick: a drop from the timer needs a landing first; off, it does not.
	tongue.clear()
	player.end_climb()
	_put(world, Vector2i(17, 9))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	await until(func() -> bool: return not player.climbing(), 60)
	await until(func() -> bool: return not tongue.active and tongue.cooldown_left <= 0.0, 30)
	ok = check(not player.is_on_floor() and player.climb_locked(), "after the time runs out with the toggle on he is locked while in the air") and ok
	tongue.lash()
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "a lash in the air after the drop does not stick") and ok
	await until(func() -> bool: return player.is_on_floor(), 120)
	await until(func() -> bool: return tongue.cooldown_left <= 0.0, 30)
	ok = check(not player.climb_locked(), "landing lifts it") and ok
	player.facing = 1
	tongue.lash()
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0, "and he sticks again") and ok
	ab.climb_land_to_restick = false
	tongue.clear()
	_put(world, Vector2i(17, 9))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	await until(func() -> bool: return not player.climbing(), 60)
	await until(func() -> bool: return not tongue.active and tongue.cooldown_left <= 0.0, 30)
	tongue.lash()
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0, "with the toggle off he sticks again at once after a drop") and ok

	# Breakable walls: the hit lands either way; he sticks only if the toggle is on and the wall still stands.
	tongue.clear()
	var room: Room = world.current
	ab.climb_breakable = true
	_put(world, Vector2i(23, 16))
	tongue.lash()
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0 and _damage(room) == 1, "he sticks to a breakable wall, which takes a hit (%d)" % _damage(room)) and ok
	player.scripted_jump_pressed = true
	await physics_frame
	await until(func() -> bool: return player.is_on_floor(), 120)
	await until(func() -> bool: return not tongue.active and tongue.cooldown_left <= 0.0, 90)
	player.facing = 1
	tongue.lash()
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"] and room.info.broken.has(WALL), "the hit that breaks the wall does not stick") and ok
	world._place_in("1")
	room = world.current
	player = world.get_node("Player")
	ab.climb_breakable = false
	_put(world, Vector2i(23, 16))
	tongue.lash()
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"] and _damage(room) == 1, "with the toggle off the wall takes the hit and he does not stick") and ok
	ab.climb_breakable = true

	# Ceilings.
	tongue.clear()
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0 and player.climbing_ceiling(), "an up-lash at the slab hangs him from it") and ok
	ok = check(absf(player.global_position.y - (120.0 + 5.0 + MovementSim.CLIMB_GAP)) < 0.01, "a gap under it (y %.2f)" % player.global_position.y) and ok
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(not player.climbing() and player.velocity.y > -1.0, "jump there lets go and drops (%.0f)" % player.velocity.y) and ok
	for i in 4:
		await physics_frame
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(is_equal_approx(player.velocity.y, -player.config.air_jump_speed), "with the double jump ready") and ok
	tongue.clear()
	ab.climb_ceiling = false
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "with ceilings off an up-lash is what it was") and ok
	ab.climb_ceiling = true

	# An Imprint platform is not stuck to.
	tongue.clear()
	_put(world, Vector2i(14, 13))
	world.imprint.platforms.append(ImprintPlatform.new(Rect2(Vector2(170, 130), Vector2(20, 10)), 10.0, false))
	tongue.lash()
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "an Imprint platform stops the tongue but is not stuck to") and ok
	world.imprint.clear(false)

	# Something other than the tongue's wall in the way: pulled as far as he can go, then he lets go.
	ok = _blocked_short() and ok

	# Letting go from outside.
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	tongue.clear()
	ok = check(not player.climbing() and not tongue.active, "clearing the tongue (room change, death, warp, retry) lets him go") and ok

	finish("TONGUE CLIMB", ok)


func _blocked_short() -> bool:
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var wall := Rect2(200.0, 0.0, 10.0, 300.0)
	var bump := Rect2(185.0, 148.0, 15.0, 12.0)
	var rects: Array = [wall, bump]
	var s := MovementSim.State.new()
	s.position = Vector2(150.0, 150.0)
	var started := MovementSim.start_climb(s, rects, Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, 400.0, false)
	var ok := check(started and s.climb_abort, "a ledge in the way of the pull is noticed when the climb starts")
	var released := false
	for i in 30:
		MovementSim.step(cfg, s, rects, 0.0, false, false, 1.0 / 60.0)
		if s.released:
			released = true
			break
	ok = check(released and s.climb == MovementSim.CLIMB_NONE and is_equal_approx(s.position.x, 180.0), "he is pulled up to it (x %.1f) and then lets go" % s.position.x) and ok
	var free := MovementSim.State.new()
	free.position = Vector2(150.0, 150.0)
	ok = check(MovementSim.start_climb(free, [wall], Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, 400.0, false) and not free.climb_abort, "with nothing in the way the pull is for the wall") and ok
	ok = check(not MovementSim.start_climb(free, [wall], Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, 400.0, false), "and a body already climbing cannot start another") and ok
	return ok


func _defaults(ab: Abilities) -> bool:
	var ok := check(not ab.tongue_climb and ab.climb_hold == 0.5 and ab.climb_wiggle == 0.2 and ab.climb_zip_speed == 400.0, "the starting values are 0.5 s, a 0.2 s wiggle and a 400 px/s pull, off")
	ok = check(ab.climb_breakable and ab.climb_ceiling and not ab.climb_land_to_restick, "breakable and ceilings on, land before re-stick off") and ok
	var round_trip := Abilities.from_dict(ab.to_dict())
	return check(round_trip.climb_hold == ab.climb_hold and round_trip.climb_breakable == ab.climb_breakable, "they round-trip through a save") and ok


## Puts the player in a cell of the fixture room, facing right, and clears the tongue.
func _put(world: Node, cell: Vector2i) -> void:
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	tongue.clear()
	player.scripted_x = 0.0
	player.place(world.current.position + Grid.cell_center(cell), world.current.world_rects())
	player.facing = 1


## Plays on until the tongue is back in; says whether Freddy climbed meanwhile.
func _watch(player: Player, tongue: Node) -> Dictionary:
	var climbed := false
	for i in 120:
		await physics_frame
		climbed = climbed or player.climbing()
		if not tongue.active:
			break
	return {"climbed": climbed}


## Hits the wall has taken, or -1 if it is gone.
func _damage(room: Room) -> int:
	var wall := room.wall_at(Rect2(Vector2(262.0, 142.0), Vector2(2, 2)))
	return wall.damage if wall != null else -1
