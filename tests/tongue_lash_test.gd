extends SceneTree

## Tongue Lash and breakable walls. In room 7, the walls around the health pip:
## no lash before Tongue Lash is found, the tongue goes the way the player faces
## from the mouth at the set speed as far as the set length, comes back in, the
## cooldown limits the rate, a wall takes two hits (or the dev test's number),
## breaking it stops it colliding, and it is back when the room is built again. A string room checks that a player stands on an intact
## wall and not on a broken one. Space lashes and does not jump.

const WALL := "r7_pipwall"
## The lash this test was written for: a steady 220 px/s out and an accelerating
## snap back at 3.5 times that, with no creep and no stick. The starting values are
## a frog's (see tests/tongue_motion_test.gd), so the lash flows here set these.
const STEADY := {
	"tongue_speed": 220.0, "tongue_snap": 3.5, "tongue_creep": 0.0, "tongue_creep_reach": 0.0,
	"tongue_ramp": 0.0, "tongue_strike": 1.0, "tongue_settle": 0.0, "tongue_stick": 0.0, "tongue_pad": false,
}


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := true
	var state: Node = root.get_node("GameState")
	var dev: Node = root.get_node("DevSession")
	state.reset()
	ok = _keys() and ok
	ok = _abilities() and ok
	ok = _fixture() and ok

	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	player.scripted = true
	tongue.scripted = true
	var room: Room = world.current
	# On the exit 2 ledge, facing left at the wall.
	_stand(world, player, Vector2i(24, 34))
	player.facing = -1
	await physics_frame
	await physics_frame
	var rects_before := player.solids.size()

	ok = _check(not tongue.lash() and not tongue.active, "before Tongue Lash is found, nothing lashes") and ok
	tongue.scripted_lash = true
	await physics_frame
	ok = _check(not tongue.active, "and neither does the key") and ok
	state.abilities.tongue_unlocked = true
	for stat in STEADY:
		state.abilities.set(stat, STEADY[stat])

	# The tongue starts at the mouth, the way the player faces, and goes out at the set speed.
	ok = _check(tongue.lash(), "with Tongue Lash, a press lashes") and ok
	var tip: Vector2 = tongue.tip()
	ok = _check(tongue.direction == -1 and is_equal_approx(tip.y, player.global_position.y - 1.5) and tip.x < player.global_position.x, "the tip starts at the front of the body, on the mouth row") and ok
	await physics_frame
	await physics_frame
	ok = _check(is_equal_approx(tongue.extension, 2.0 * 220.0 / 60.0), "and goes out at the lash speed (%.1f px in two ticks)" % tongue.extension) and ok
	var body := player.get_node("Visual") as PlayerBody
	var drawn := body.tongue_rect(tongue.extension)
	ok = _check(drawn.size.y == 1.0 and drawn.position.x < body.position.x and drawn.end.x > body.position.x, "the pink line is one pixel high and leaves the front of the body (%s)" % drawn) and ok

	# One tongue at a time, and the cooldown runs from the tongue being back in.
	ok = _check(not tongue.lash(), "a second press while the tongue is out does nothing") and ok
	await _wait(tongue, 60)
	ok = _check(not tongue.active and tongue.cooldown_left > 0.0 and not tongue.lash(), "the tongue comes back in, and a press inside the cooldown does nothing") and ok
	ok = _check(_damage(room) == 1 and not room.info.broken.has(WALL), "the lash cracked the wall once (%d hits)" % _damage(room)) and ok
	ok = _check(room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) != null, "while it stands, the wall is there to hit") and ok

	# Lashed again after the cooldown: the second hit breaks it.
	await _lash_again(tongue)
	ok = _check(room.info.broken.has(WALL) and room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) == null, "the second hit breaks the whole wall") and ok
	ok = _check(player.solids.size() == rects_before - 15, "and the player stops colliding with its fifteen cells (%d to %d)" % [rects_before, player.solids.size()]) and ok

	# Out of reach: the tongue goes as far as its length and no further, and breaks nothing.
	player.facing = 1
	tongue.cooldown_left = 0.0
	ok = _check(tongue.lash(), "a lash fires to the right") and ok
	var farthest := await _wait(tongue, 90)
	ok = _check(is_equal_approx(farthest, 50.0) and room.info.broken.size() == 1, "and stops at the tongue's length, short of the wall (%.1f px)" % farthest) and ok
	state.abilities.tongue_length = 20.0
	player.facing = -1
	tongue.cooldown_left = 0.0
	tongue.lash()
	farthest = await _wait(tongue, 90)
	ok = _check(is_equal_approx(farthest, 20.0), "a shorter tongue goes only that far (%.1f px)" % farthest) and ok
	state.abilities.tongue_length = 50.0

	# Turning round cuts the lash short.
	player.facing = 1
	tongue.cooldown_left = 0.0
	tongue.lash()
	await physics_frame
	player.facing = -1
	await physics_frame
	ok = _check(not tongue.active and tongue.cooldown_left > 0.0, "turning round pulls the tongue in at once") and ok

	# The wall is back when the room is built again, and the tongue is gone.
	player.facing = -1
	tongue.cooldown_left = 0.0
	tongue.lash()
	ok = _check(world.warp_to("7"), "warp into room 7 again") and ok
	await process_frame
	room = world.current
	ok = _check(room.info.broken.is_empty() and _damage(room) == 0 and not tongue.active and tongue.cooldown_left == 0.0, "the wall is whole again, and no lash or cooldown carries over") and ok
	ok = _check(room.world_rects().size() == room.info.all_solids().size(), "and the room collides with it") and ok

	# The dev test's wall strength.
	_stand(world, player, Vector2i(24, 34))
	player.facing = -1
	await physics_frame
	dev.mode = dev.Mode.DEV_TEST
	ok = _check(dev.wall_strength() == 2, "the default wall strength is 2") and ok
	ok = _check(dev.set_wall_strength(world, 0) != "" and dev.set_wall_strength(world, 100) != "" and dev.wall_strength() == 2, "a strength of 0 or 100 is refused") and ok
	ok = _check(dev.set_wall_strength(world, 1) == "" and dev.wall_strength() == 1, "a dev test can set it to 1") and ok
	tongue.cooldown_left = 0.0
	tongue.lash()
	await _wait(tongue, 60)
	ok = _check(room.info.broken.has(WALL), "and then one lash breaks the wall") and ok
	dev.mode = dev.Mode.NORMAL
	ok = _check(dev.wall_strength() == 2, "outside a dev test the strength is always 2") and ok
	dev.wall_strength_override = 0

	# Nothing lashes while the world is busy or input is blocked, and a busy world pulls it in.
	world.warp_to("7")
	await process_frame
	_stand(world, player, Vector2i(24, 34))
	tongue.cooldown_left = 0.0
	world._busy = true
	ok = _check(not tongue.lash(), "no lash while the world is busy") and ok
	world._busy = false
	world.modal_owner = "test"
	ok = _check(not tongue.lash(), "or while a panel has the input") and ok
	world.modal_owner = ""
	ok = _check(tongue.lash(), "and it lashes again once they are over") and ok
	world._busy = true
	await physics_frame
	await physics_frame
	ok = _check(not tongue.active, "a tongue out when the world goes busy is pulled in") and ok
	world._busy = false

	# The snap back: the tongue goes out at tongue_speed and comes back faster,
	# speeding up, and a faster tongue snaps back faster too.
	world.warp_to("7")
	await process_frame
	_stand(world, player, Vector2i(24, 34))
	player.facing = 1
	tongue.cooldown_left = 0.0
	tongue.lash()
	var base := await _trace(tongue, 90)
	ok = _check(base["out"] == 14 and base["back"] == 4, "at 220 px/s a full lash takes 14 ticks out and 4 back (%d, %d)" % [base["out"], base["back"]]) and ok
	var legs: Array = base["legs"]
	ok = _check(legs.size() >= 3 and legs[0] < legs[1] and legs[1] < legs[2], "the snap speeds up as it comes in (%s px a tick)" % str(legs)) and ok
	ok = _check(legs[0] > 220.0 / 60.0 and legs[2] > 3.0 * 220.0 / 60.0, "it starts faster than the way out and ends well over three times it") and ok
	state.abilities.tongue_speed = 560.0
	tongue.cooldown_left = 0.0
	tongue.lash()
	var fast := await _trace(tongue, 90)
	ok = _check(fast["out"] < base["out"] and fast["back"] < base["back"] and fast["back"] == 2, "doubling the lash speed shortens the snap as well as the reach (%d out, %d back)" % [fast["out"], fast["back"]]) and ok
	state.abilities.tongue_speed = 220.0
	state.abilities.tongue_snap = 6.0
	tongue.cooldown_left = 0.0
	tongue.lash()
	var sharp := await _trace(tongue, 90)
	ok = _check(sharp["out"] == 14 and sharp["back"] < base["back"], "a bigger snap shortens only the way back (%d out, %d back)" % [sharp["out"], sharp["back"]]) and ok
	state.abilities.tongue_snap = 1.0
	tongue.cooldown_left = 0.0
	tongue.lash()
	var steady := await _trace(tongue, 90)
	var even := true
	var steady_legs: Array = steady["legs"]
	for leg in steady_legs:
		even = even and is_equal_approx(leg, 220.0 / 60.0)
	ok = _check(even and steady["back"] == 14, "a snap of 1 comes back at the speed it went out (%d ticks)" % steady["back"]) and ok
	state.abilities.tongue_snap = 3.5
	# A short lash against the wall keeps the same proportion.
	player.facing = -1
	tongue.cooldown_left = 0.0
	tongue.lash()
	var hit := await _trace(tongue, 90)
	var reach: float = hit["reach"]
	var expected := ceili(reach / (3.5 * 220.0) * 60.0 - 0.0001)
	ok = _check(reach < 50.0 and hit["back"] == expected, "a lash that hits at %.1f px snaps back in proportion (%d ticks, expected %d)" % [reach, hit["back"], expected]) and ok
	# Turned round at no length, the return has nothing to speed up.
	tongue.clear()
	tongue.extension = 0.0
	tongue._begin_return()
	ok = _check(tongue.phase == tongue.Phase.BACK and tongue._back_duration == 0.0, "a lash that hits at once has no return to work out") and ok
	tongue.clear()

	world.queue_free()
	await process_frame
	state.reset()
	print("TONGUE LASH %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Space lashes, W and Up jump, and Space no longer jumps.
func _keys() -> bool:
	var ok := true
	var jump := _keycodes("jump")
	var lash := _keycodes("lash")
	ok = _check(not jump.has(KEY_SPACE) and jump.has(KEY_W) and jump.has(KEY_UP), "jump is W and Up, not Space") and ok
	ok = _check(lash == [KEY_SPACE], "lash is Space") and ok
	return ok


func _keycodes(action: String) -> Array:
	var out := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append((event as InputEventKey).physical_keycode)
	return out


func _abilities() -> bool:
	var ok := true
	var abilities := Abilities.new()
	ok = _check(not abilities.tongue_unlocked and is_equal_approx(abilities.tongue_cooldown, 0.15) and is_equal_approx(abilities.tongue_speed, 220.0) and is_equal_approx(abilities.tongue_snap, 2.5) and is_equal_approx(abilities.tongue_length, 50.0), "Tongue Lash starts locked, with a 0.15 s cooldown, 220 px/s out, a 2.5x snap back and 50 px of reach") and ok
	ok = _check(abilities.apply(Upgrades.get_def("tongue_lash"), true) and abilities.tongue_unlocked and not abilities.apply(Upgrades.get_def("tongue_lash"), true), "the Tongue Lash upgrade unlocks it once") and ok
	ok = _check(abilities.apply(Upgrades.get_def("tongue_cooldown"), 0.1) and not abilities.apply(Upgrades.get_def("tongue_cooldown"), 0.15) and is_equal_approx(abilities.tongue_cooldown, 0.1), "a cooldown upgrade only lowers it") and ok
	ok = _check(abilities.apply(Upgrades.get_def("tongue_speed"), 500.0) and not abilities.apply(Upgrades.get_def("tongue_speed"), 100.0) and is_equal_approx(abilities.tongue_speed, 500.0), "a speed upgrade only raises it") and ok
	ok = _check(abilities.apply(Upgrades.get_def("tongue_length"), 80.0) and not abilities.apply(Upgrades.get_def("tongue_length"), 60.0) and is_equal_approx(abilities.tongue_length, 80.0), "a length upgrade only raises it") and ok
	ok = _check(abilities.apply(Upgrades.get_def("tongue_snap"), 5.0) and not abilities.apply(Upgrades.get_def("tongue_snap"), 2.0) and is_equal_approx(abilities.tongue_snap, 5.0), "a snap upgrade only raises it") and ok
	var back := Abilities.from_dict(abilities.to_dict())
	ok = _check(back.tongue_unlocked and is_equal_approx(back.tongue_cooldown, 0.1) and is_equal_approx(back.tongue_speed, 500.0) and is_equal_approx(back.tongue_length, 80.0), "Tongue Lash round-trips through a save") and ok
	ok = _check(is_equal_approx(back.tongue_snap, 5.0) and is_equal_approx(Abilities.from_dict({"tongue_snap": 0.2}).tongue_snap, 1.0), "the snap round-trips too, and a save cannot make it slower than a steady return") and ok
	ok = _check(is_equal_approx(Abilities.from_dict({"tongue_speed": 400.0}).tongue_speed, 400.0) and is_equal_approx(Abilities.from_dict({"tongue_speed": 400.0}).tongue_snap, 2.5), "a save holding the old 400 px/s keeps it, and takes the 2.5x snap") and ok
	var old := Abilities.from_dict({})
	ok = _check(not old.tongue_unlocked and is_equal_approx(old.tongue_cooldown, 0.15), "and a new save loads it locked") and ok
	var gun_save := Abilities.from_dict({"gun_unlocked": true, "gun_cooldown": 0.5, "gun_shot_speed": 900.0})
	ok = _check(gun_save.tongue_unlocked and is_equal_approx(gun_save.tongue_cooldown, 0.15) and is_equal_approx(gun_save.tongue_speed, 220.0) and is_equal_approx(gun_save.tongue_snap, 2.5), "a save from the gun keeps the power and takes the new tuning")  and ok
	var loadout := DevCatalog.reconcile({"abilities": {"gun_unlocked": true, "gun_cooldown": 0.5, "gun_shot_speed": 900.0}})
	ok = _check(loadout["error"] == "" and loadout["warnings"].is_empty() and loadout["loadout"]["abilities"]["tongue_unlocked"] and is_equal_approx(loadout["loadout"]["abilities"]["tongue_cooldown"], 0.5) and is_equal_approx(loadout["loadout"]["abilities"]["tongue_speed"], 900.0), "a stored loadout from the gun keeps its chosen values") and ok
	return ok


## A platform of breakable wall in a string room: solid and stood on while it
## stands, open once broken, and the room as loaded is untouched.
func _fixture() -> bool:
	var ok := true
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += "B" if (y == 12 and x >= 5 and x <= 10) else ("P" if (x == 2 and y == 16) else ("#" if edge else "."))
		rows.append(row)
	var errors: Array[String] = []
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i(0, 0), "text": "legend:\n  B = breakable id=b1\n---\n" + "\n".join(rows) + "\n"}], "1", errors)
	ok = _check(errors.is_empty(), "a room with a breakable wall loads %s" % [errors]) and ok
	var loaded: RoomInfo = built["rooms"]["1"]
	ok = _check(loaded.breakables.get("b1", []).size() == 6 and loaded.is_solid(7, 12) and not loaded.solids.any(func(r: Rect2i) -> bool: return r.has_point(Vector2i(7, 12))), "its six cells are solid but are not in the room's plain solids") and ok
	var room := Room.new()
	room.build(loaded)
	var above := Vector2(75.0, 115.0)
	ok = _check(MovementSim.standing(above, room.world_rects()), "a player stands on the wall while it stands") and ok
	var wall := room.wall_at(Rect2(Vector2(72, 122), Vector2(2, 2)))
	ok = _check(wall != null and not room.hit_wall(wall, 2) and room.wall_at(Rect2(Vector2(72, 122), Vector2(2, 2))) != null, "one of two hits leaves it standing") and ok
	ok = _check(room.hit_wall(wall, 2) and not MovementSim.standing(above, room.world_rects()), "the second breaks it, and the player no longer stands there") and ok
	ok = _check(not room.info.is_solid(7, 12) and loaded.is_solid(7, 12) and loaded.broken.is_empty(), "the room as loaded is untouched, so a new Room has the wall again") and ok
	var again := Room.new()
	again.build(loaded)
	ok = _check(MovementSim.standing(above, again.world_rects()), "a room built again has it whole") and ok
	var open := loaded.variant(["b1"] as Array[String])
	ok = _check(not open.is_solid(7, 12) and open.all_solids().size() == loaded.all_solids().size() - 6, "a variant with it broken has those cells open") and ok
	room.free()
	again.free()
	return ok


func _stand(world: Node, player: Player, cell: Vector2i) -> void:
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(cell), room.world_rects())
	player.facing = 1


## Hits the wall has taken in room 7, or -1 if it is gone.
func _damage(room: Room) -> int:
	var wall := room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2)))
	return wall.damage if wall != null else -1


## Plays on until the tongue is back in, or `limit` ticks have passed. Returns
## the farthest it went.
func _wait(tongue: Node, limit: int) -> float:
	var farthest := 0.0
	for i in limit:
		await physics_frame
		farthest = maxf(farthest, tongue.extension)
		if not tongue.active:
			break
	return farthest


## Plays on until the tongue is back in, and says how many ticks it took out
## (`out`) and back (`back`), how far it reached (`reach`), and how far it came
## in on each tick but the last (`legs`).
func _trace(tongue: Node, limit: int) -> Dictionary:
	var out := 0
	var back := 0
	var reach := 0.0
	var legs: Array = []
	var last: float = tongue.extension
	for i in limit:
		await physics_frame
		if not tongue.active:
			back += 1
			break
		if tongue.extension == last and not tongue.retracting:
			# The frame ran before the tongue's own tick.
			continue
		if tongue.extension > last:
			out += 1
		else:
			back += 1
			legs.append(last - tongue.extension)
		reach = maxf(reach, tongue.extension)
		last = tongue.extension
	return {"out": out, "back": back, "reach": reach, "legs": legs}


## Waits out the cooldown, lashes, and waits for the tongue to come back.
func _lash_again(tongue: Node) -> void:
	for i in 60:
		if not tongue.active and tongue.cooldown_left <= 0.0:
			break
		await physics_frame
	tongue.lash()
	await _wait(tongue, 90)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
