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
## TongueLash.Phase.STICK.
const STICK_PHASE := 1


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
	ab.tongue_length = 60.0 # the fixture's distances were laid out for the old length

	# Power-up off: a lash at the pillar sticks the tip for a moment and comes back; Freddy stays put.
	_put(world, Vector2i(17, 12))
	tongue.lash()
	var saw := await _watch(player, tongue)
	ok = check(not saw["climbed"] and is_equal_approx(player.global_position.x, 175.0), "with the power-up off a lash pulls nothing (x %.1f)" % player.global_position.x) and ok

	# A plain lash, even stuck to the wall, is drawn at its own length: the overhang is for climbs only.
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return tongue.phase == STICK_PHASE, 60)
	ok = check(tongue.drawn_length() == tongue.extension, "a plain lash's stuck tongue is drawn at its length (%.1f, extension %.1f)" % [tongue.drawn_length(), tongue.extension]) and ok
	await _watch(player, tongue)

	# Pressed to the wall: the lash hits at once and the tongue still shows, past the face.
	ab.tongue_climb = true
	_put(world, Vector2i(19, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	var pressed_body := player.get_node("Visual") as PlayerBody
	ok = check(tongue.drawn_length() >= tongue.CLIMB_OVERHANG and is_equal_approx(pressed_body.tongue_rect(tongue.drawn_length()).end.x, 200.0 + tongue.CLIMB_OVERHANG), "pressed to the wall, the tongue still ends past the face (length %.1f)" % tongue.drawn_length()) and ok
	tongue.clear()
	player.end_climb()

	# On: pulled to the wall, hung there with gravity off.
	_put(world, Vector2i(17, 12))
	ok = check(tongue.lash(), "a lash is made") and ok
	var got := await until(func() -> bool: return player.hanging(), 60)
	ok = check(got >= 0 and tongue.phase == CLIMB_PHASE, "a lash that hits the pillar pulls him to it (%d ticks) and the tongue holds" % got) and ok
	ok = check(absf(player.global_position.x - HANG_X) < 0.01, "he hangs a gap short of the face, at x %.2f (expected %.2f)" % [player.global_position.x, HANG_X]) and ok
	var body := player.get_node("Visual") as PlayerBody
	ok = check(is_equal_approx(tongue.drawn_length(), 200.0 - player.global_position.x - 5.0 + tongue.CLIMB_OVERHANG), "the drawn tongue ends %d px past the wall's face (length %.1f)" % [int(tongue.CLIMB_OVERHANG), tongue.drawn_length()]) and ok
	ok = check(is_equal_approx(body.tongue_rect(tongue.drawn_length()).end.x - body.position.x, 10.0 + roundf(tongue.drawn_length())), "and the drawn line is that long from the body") and ok
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

	# With the toggle on, a tap at it is still only a hit: the hold decides whether he sticks.
	tongue.scripted_held = false
	var hits := _damage(room)
	tongue.clear()
	_put(world, Vector2i(23, 16))
	tongue.lash()
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"] and _damage(room) != hits, "a tap at a breakable wall hits it and does not climb") and ok
	tongue.scripted_held = true
	tongue.clear()

	# Ceilings.
	tongue.clear()
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0 and player.climbing_ceiling(), "an up-lash at the slab hangs him from it") and ok
	ok = check(absf(player.global_position.y - (120.0 + 5.0 + MovementSim.CLIMB_GAP)) < 0.01, "a gap under it (y %.2f)" % player.global_position.y) and ok
	ok = check(is_equal_approx(tongue.drawn_length(), player.global_position.y - 120.0 - 5.0 + tongue.CLIMB_OVERHANG), "the drawn tongue reaches %d px into the slab (length %.1f)" % [int(tongue.CLIMB_OVERHANG), tongue.drawn_length()]) and ok
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(not player.climbing() and player.velocity.y > -1.0, "jump there lets go and drops (%.0f)" % player.velocity.y) and ok
	for i in 4:
		await physics_frame
	player.scripted_jump_pressed = true
	await physics_frame
	ok = check(is_equal_approx(player.velocity.y, -player.config.air_jump_speed), "and the next press is a full jump (the spare jump from the ceiling)") and ok
	tongue.clear()
	ab.climb_ceiling = false
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "with ceilings off an up-lash is what it was") and ok
	ab.climb_ceiling = true

	# Both jumps are kept when he lets go: off a wall a press as the hang runs out is a full jump.
	tongue.clear()
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	await until(func() -> bool: return not player.climbing(), 60)
	await physics_frame
	var first := await _press(player)
	await ticks(4)
	var second := await _press(player)
	await ticks(4)
	var third := await _press(player)
	ok = check(first == "ground" and second == "air" and third == "none", "pressing as the hang runs out is a full jump, then the double jump, then nothing (%s, %s, %s)" % [first, second, third]) and ok
	# ...but only for the ledge's coyote time (0.1 s); after that it is the air jump.
	tongue.clear()
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	await until(func() -> bool: return not player.climbing(), 60)
	await ticks(10)
	first = await _press(player)
	await ticks(4)
	second = await _press(player)
	ok = check(first == "air" and second == "none", "a press well after he has dropped is only the air jump (%s, %s)" % [first, second]) and ok
	# From a ceiling he gets a full jump and the double jump, wherever in the fall he presses.
	for how in ["jump", "time"]:
		tongue.clear()
		_put(world, Vector2i(12, 5))
		tongue.lash(true)
		await until(func() -> bool: return player.hanging() and player.climbing_ceiling(), 60)
		if how == "jump":
			var dropped := await _press(player)
			ok = check(dropped == "none" and not player.climbing(), "jump under the ceiling drops him and is not itself a jump") and ok
		else:
			await until(func() -> bool: return not player.climbing(), 60)
		await ticks(4)
		first = await _press(player)
		await ticks(4)
		second = await _press(player)
		await ticks(4)
		third = await _press(player)
		ok = check(first == "ground" and second == "air" and third == "none", "dropped from a ceiling by %s: a full jump, the double jump, then nothing (%s, %s, %s)" % [how, first, second, third]) and ok
	tongue.clear()
	_put(world, Vector2i(12, 5))
	tongue.lash(true)
	await until(func() -> bool: return player.hanging() and player.climbing_ceiling(), 60)
	await _press(player)
	await until(func() -> bool: return player.is_on_floor(), 120)
	ok = check(not player._state.spare_jump, "landing takes the spare jump away") and ok

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

	# Taking the power away in the dev tools drops him at once: nothing is given back.
	tongue.clear()
	var hold_was := ab.climb_hold
	ab.climb_hold = 5.0
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	var loadout: Dictionary = DevCatalog.capture(state.to_dict())
	loadout["abilities"]["tongue_climb"] = false
	state.set_loadout(loadout)
	ab = state.abilities
	await physics_frame
	ok = check(not player.climbing() and not tongue.active or tongue.phase != CLIMB_PHASE, "turning Tongue Climb off in the dev tools while he hangs drops him and the tongue goes back") and ok
	first = await _press(player)
	second = await _press(player)
	ok = check(first == "air" and second == "none", "with no grace jump, and the double jump he got from sticking kept (%s, %s)" % [first, second]) and ok
	ab.tongue_climb = true
	ab.climb_zip_speed = 100.0
	tongue.clear()
	_put(world, Vector2i(16, 12))
	tongue.lash()
	await until(func() -> bool: return player.climbing() and not player.hanging(), 60)
	ok = check(player.climbing() and not player.hanging(), "caught while being pulled") and ok
	ab.tongue_climb = false
	state.abilities_changed.emit()
	await physics_frame
	ok = check(not player.climbing(), "turning it off during the pull drops him too") and ok
	ab.tongue_climb = true
	ab.climb_zip_speed = 400.0
	tongue.clear()
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	ab.tongue_unlocked = false
	state.abilities_changed.emit()
	await physics_frame
	ok = check(not player.climbing() and not tongue.active, "taking Tongue Lash away clears the tongue and drops him") and ok
	ab.tongue_unlocked = true
	tongue.clear()
	_put(world, Vector2i(12, 5))
	tongue.lash(true)
	await until(func() -> bool: return player.hanging() and player.climbing_ceiling(), 60)
	ab.climb_ceiling = false
	state.abilities_changed.emit()
	await physics_frame
	ok = check(not player.climbing(), "turning ceilings off drops him from a ceiling") and ok
	first = await _press(player)
	ok = check(first == "air", "with no spare jump (%s)" % first) and ok
	ab.climb_ceiling = true
	tongue.clear()
	_put(world, Vector2i(23, 16))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	ab.climb_breakable = false
	state.abilities_changed.emit()
	await physics_frame
	ok = check(not player.climbing(), "turning breakable walls off drops him from one") and ok
	ab.climb_breakable = true
	ab.climb_hold = hold_was

	# Letting go from outside.
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return player.hanging(), 60)
	tongue.clear()
	ok = check(not player.climbing() and not tongue.active, "clearing the tongue (room change, death, warp, retry) lets him go") and ok

	ok = await _hold_cases(world, player, tongue, ab) and ok

	# A fast pull over spikes still kills him: the whole path is tested, not just where he ends.
	tongue.clear()
	ab.climb_zip_speed = 2000.0
	_put(world, Vector2i(16, 3))
	var spike_room: Room = world.current
	tongue.lash()
	var touched := false
	var end_alone := false
	for i in 30:
		await physics_frame
		if spike_room.touches_hazard(player.hazard_rect()):
			touched = true
			end_alone = spike_room.touches_hazard(player.body_rect())
			break
	ok = check(touched and not end_alone, "a pull that passes over spikes touches them although he ends clear of them") and ok

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
	ok = _platform_in_the_way() and ok
	var free := MovementSim.State.new()
	free.position = Vector2(150.0, 150.0)
	ok = check(MovementSim.start_climb(free, [wall], Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, 400.0, false) and not free.climb_abort, "with nothing in the way the pull is for the wall") and ok
	ok = check(not MovementSim.start_climb(free, [wall], Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, 400.0, false), "and a body already climbing cannot start another") and ok
	return ok


## The review's case: the tongue (y = 148.5) clears a 10 x 10 platform at
## (170, 150), but the body, 145 to 155, cannot. The climb is started knowing only
## the room's solids (as it was in the review), so the pull itself has to meet the
## platform: it stops there and lets go (never crushed, never inside it), at any
## pull speed.
func _platform_in_the_way() -> bool:
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var wall := Rect2(200.0, 0.0, 10.0, 300.0)
	var movers := Movers.new([PlatformPath.new("p", Rect2i(17, 15, 1, 1), Vector2i.DOWN, 1, 10.0, 100.0)])
	var ok := true
	for speed in [400.0, 2000.0]:
		var s := MovementSim.State.new()
		s.position = Vector2(160.0, 150.0)
		var started := MovementSim.start_climb(s, [wall], Vector2(201.0, 148.5), Vector2.RIGHT, 0.5, speed, false)
		var released := false
		for tick in 30:
			MovementSim.step(cfg, s, [wall], 0.0, false, false, 1.0 / 60.0, movers, tick)
			if s.released:
				released = true
				break
		var box := Rect2(s.position - MovementSim.HALF, MovementSim.HALF * 2.0)
		ok = check(started and released and not s.crushed and not box.intersects(movers.rects(1)[0]), "a platform the tongue clears but the body cannot stops the pull at %.0f px/s (x %.1f, crushed %s)" % [speed, s.position.x, s.crushed]) and ok
	return ok


## Holding the lash key decides whether a lash that sticks climbs: a tap only
## lashes, a hold past `climb_press` climbs, and a lash held but not yet long
## enough waits stuck to the wall for the key to be let go or held on.
func _hold_cases(world: Node, player: Player, tongue: Node, ab: Abilities) -> bool:
	var ok := check(ab.climb_press == 0.15, "the lash must be held 0.15 s to climb at the start")
	ok = check(Abilities.from_dict(ab.to_dict()).climb_press == 0.15 and Abilities.from_dict({"climb_press": -1.0}).climb_press >= 0.0, "it round-trips and is never negative") and ok
	var room: Room = world.current
	ab.tongue_climb = true
	ab.climb_breakable = true
	ab.climb_ceiling = true
	ab.climb_land_to_restick = false

	# A tap is only a lash, even against a wall.
	tongue.scripted_held = false
	_put(world, Vector2i(17, 12))
	tongue.lash()
	var saw := await _watch(player, tongue)
	ok = check(not saw["climbed"], "a tap at a near wall does not climb") and ok

	# Held at a wall too near for the hold to have run out: the tip waits stuck.
	tongue.scripted_held = true
	_put(world, Vector2i(17, 12))
	tongue.lash()
	ok = check(await until(func() -> bool: return tongue.phase == 1, 30) >= 0, "a held lash at a near wall sticks") and ok
	ok = check(not player.climbing() and tongue.active, "and waits there, with Freddy still on the floor") and ok
	await physics_frame
	ok = check(tongue.phase == 1 and not player.climbing(), "the wait does not run out while X is held") and ok
	tongue.scripted_held = false
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "let go before the hold, the lash returns as a plain lash") and ok

	# Held on past the hold: it climbs from where it stuck.
	tongue.scripted_held = true
	_put(world, Vector2i(17, 12))
	tongue.lash()
	var got := await until(func() -> bool: return player.hanging(), 60)
	ok = check(got >= 0 and tongue.phase == CLIMB_PHASE, "held long enough, the waiting lash climbs (%d ticks)" % got) and ok
	ok = check(absf(player.global_position.x - HANG_X) < 0.01, "and he hangs at the same place (x %.2f)" % player.global_position.x) and ok
	tongue.clear()

	# Held at a farther wall: the hold is over by the time the tip sticks, so no wait.
	_put(world, Vector2i(15, 12))
	tongue.lash()
	got = await until(func() -> bool: return player.hanging(), 60)
	ok = check(got >= 0 and tongue.phase == CLIMB_PHASE, "a hold at a far wall climbs") and ok
	tongue.clear()

	# Once the hold is made, letting go before the tip arrives still climbs.
	ab.climb_press = 0.05
	_put(world, Vector2i(17, 12))
	tongue.lash()
	for i in 4:
		await physics_frame
	tongue.scripted_held = false
	got = await until(func() -> bool: return player.hanging(), 60)
	ok = check(got >= 0, "held for the hold and then let go, the tip still climbs") and ok
	tongue.clear()
	ab.climb_press = 0.15

	# A waiting up-lash climbs from where the tip stuck, though Freddy falls while it waits.
	tongue.scripted_held = true
	ab.climb_press = 0.5
	_put(world, Vector2i(7, 14))
	tongue.lash(true)
	await until(func() -> bool: return tongue.phase == 1, 30)
	await ticks(2)
	ab.climb_press = 0.0
	await physics_frame
	await until(func() -> bool: return player.hanging(), 60)
	ok = check(player.climbing_ceiling() and absf(player.global_position.y - (120.0 + 5.0 + MovementSim.CLIMB_GAP)) < 0.01, "and hangs a gap under the slab, not where he had moved to (y %.2f)" % player.global_position.y) and ok
	tongue.clear()
	ab.climb_press = 0.15
	tongue.scripted_held = false

	# A ceiling: a tap does not hang, a hold does.
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "a tap up at the slab does not hang him") and ok
	tongue.scripted_held = true
	_put(world, Vector2i(7, 16))
	tongue.lash(true)
	ok = check(await until(func() -> bool: return player.hanging() and player.climbing_ceiling(), 60) >= 0, "a hold up at the slab does") and ok
	tongue.clear()
	# The real C key (lash_up), held with a direction, hangs him from the slab too;
	# a tap of it only lashes.
	tongue.scripted = false
	for hold in [false, true]:
		_put(world, Vector2i(7, 16))
		Input.action_press("move_left")
		Input.action_press("lash_up")
		var hung := false
		for i in 40:
			await physics_frame
			if not hold and i == 1:
				Input.action_release("lash_up")
			hung = hung or (player.hanging() and player.climbing_ceiling())
		Input.action_release("lash_up")
		Input.action_release("move_left")
		ok = check(hung == hold, "C %s at the slab %s" % ["held" if hold else "tapped", "hangs him" if hold else "does not hang him"]) and ok
		tongue.clear()
		for i in 2:
			await physics_frame
	tongue.scripted = true

	# Zero is what it was: every lash that sticks climbs.
	ab.climb_press = 0.0
	tongue.scripted_held = false
	_put(world, Vector2i(17, 12))
	tongue.lash()
	ok = check(await until(func() -> bool: return player.hanging(), 60) >= 0, "with the hold at 0 a tap climbs") and ok
	tongue.clear()
	ab.climb_press = 0.15

	# Taking the power-up away while the tip waits sends the tongue home.
	tongue.scripted_held = true
	_put(world, Vector2i(17, 12))
	tongue.lash()
	await until(func() -> bool: return tongue.phase == 1, 30)
	ab.tongue_climb = false
	root.get_node("GameState").abilities_changed.emit()
	for i in 3:
		await physics_frame
	ok = check(tongue.phase != 1 and not player.climbing(), "turning Tongue Climb off while the tip waits sends it home") and ok
	saw = await _watch(player, tongue)
	ok = check(not saw["climbed"], "and he does not climb") and ok
	ab.tongue_climb = true
	tongue.scripted_held = true
	tongue.clear()
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


## Presses jump for one tick. Says what it did: "ground" (a ground, coyote or
## spare jump), "air" (the air jump) or "none".
func _press(player: Player) -> String:
	player.scripted_jump_pressed = true
	await physics_frame
	if player._state.air_jumped:
		return "air"
	return "ground" if player._state.jumped else "none"


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
