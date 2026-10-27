extends SceneTree

## The gun and breakable walls. In room 7, the walls around the health pip:
## no shot before the gun is found, a shot goes the way the player faces at the
## set speed, the cooldown limits the rate, a wall takes three hits (or the
## dev test's number), breaking it stops it colliding, and it is back when the
## room is built again. A string room checks that a player stands on an intact
## wall and not on a broken one. Space shoots and does not jump.

const WALL := "r7_pipwall"


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
	var gun: Node = world.get_node("Gun")
	player.scripted = true
	gun.scripted = true
	var room: Room = world.current
	# On the exit 2 ledge, facing left at the wall.
	_stand(world, player, Vector2i(24, 34))
	player.facing = -1
	await physics_frame
	await physics_frame
	var rects_before := player.solids.size()

	ok = _check(not gun.fire() and gun.shots.is_empty(), "before the gun is found, nothing fires") and ok
	gun.scripted_fire = true
	await physics_frame
	ok = _check(gun.shots.is_empty(), "and neither does the key") and ok
	state.abilities.gun_unlocked = true

	# A shot goes the way the player faces, at the set speed.
	ok = _check(gun.fire(), "with the gun, a press fires") and ok
	var shot: Shot = gun.shots[0]
	ok = _check(shot.direction == -1 and is_equal_approx(shot.position.y, player.global_position.y) and shot.position.x < player.global_position.x, "the shot starts in front of the player, on their row") and ok
	var x0 := shot.position.x
	await physics_frame
	await physics_frame
	var moved := x0 - shot.position.x
	ok = _check(is_equal_approx(moved, 2.0 * 260.0 / 60.0), "and flies left at the shot speed (%.1f px in two ticks)" % moved) and ok

	# The cooldown limits the rate.
	ok = _check(not gun.fire() and gun.cooldown_left > 0.0, "a second press inside the cooldown does nothing") and ok
	await _wait(gun, 5)
	ok = _check(gun.shots.is_empty(), "the shot ends at the wall") and ok
	ok = _check(_damage(room) == 1 and not room.info.broken.has(WALL), "and cracks it once (%d hits)" % _damage(room)) and ok
	ok = _check(room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) != null, "while it stands, the wall is there to hit") and ok

	# Fired at the wall again after each cooldown: the third hit breaks it.
	await _fire_again(gun)
	ok = _check(_damage(room) == 2 and not room.info.broken.has(WALL), "a second hit cracks it more, and it holds (%d hits)" % _damage(room)) and ok
	await _fire_again(gun)
	ok = _check(room.info.broken.has(WALL) and room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) == null, "the third hit breaks the whole wall") and ok
	ok = _check(player.solids.size() == rects_before - 15, "and the player stops colliding with its fifteen cells (%d to %d)" % [rects_before, player.solids.size()]) and ok

	# Shots stop at plain solid too.
	state.abilities.gun_unlocked = true
	player.facing = 1
	gun.cooldown_left = 0.0
	ok = _check(gun.fire(), "a shot fires to the right") and ok
	await _wait(gun, 60)
	ok = _check(gun.shots.is_empty() and room.info.broken.size() == 1 and room.info.broken.has(WALL), "and ends at the wall of the room, breaking nothing") and ok

	# The wall is back when the room is built again, and shots are gone.
	player.facing = -1
	gun.cooldown_left = 0.0
	gun.fire()
	ok = _check(world.warp_to("7"), "warp into room 7 again") and ok
	await process_frame
	room = world.current
	ok = _check(room.info.broken.is_empty() and _damage(room) == 0 and gun.shots.is_empty() and gun.cooldown_left == 0.0, "the wall is whole again, and no shot or cooldown carries over") and ok
	ok = _check(room.world_rects().size() == room.info.all_solids().size(), "and the room collides with it") and ok

	# The dev test's wall strength.
	_stand(world, player, Vector2i(24, 34))
	player.facing = -1
	await physics_frame
	dev.mode = dev.Mode.DEV_TEST
	ok = _check(dev.wall_strength() == 3, "the default wall strength is 3") and ok
	ok = _check(dev.set_wall_strength(world, 0) != "" and dev.set_wall_strength(world, 100) != "" and dev.wall_strength() == 3, "a strength of 0 or 100 is refused") and ok
	ok = _check(dev.set_wall_strength(world, 1) == "" and dev.wall_strength() == 1, "a dev test can set it to 1") and ok
	gun.cooldown_left = 0.0
	gun.fire()
	await _wait(gun, 20)
	ok = _check(room.info.broken.has(WALL), "and then one shot breaks the wall") and ok
	dev.mode = dev.Mode.NORMAL
	ok = _check(dev.wall_strength() == 3, "outside a dev test the strength is always 3") and ok
	dev.wall_strength_override = 0

	# Nothing fires while the world is busy or input is blocked.
	world.warp_to("7")
	await process_frame
	_stand(world, player, Vector2i(24, 34))
	gun.cooldown_left = 0.0
	world._busy = true
	ok = _check(not gun.fire(), "no shot while the world is busy") and ok
	world._busy = false
	world.modal_owner = "test"
	ok = _check(not gun.fire(), "or while a panel has the input") and ok
	world.modal_owner = ""
	ok = _check(gun.fire(), "and it fires again once they are over") and ok

	world.queue_free()
	await process_frame
	state.reset()
	print("GUN %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Space shoots, W and Up jump, and Space no longer jumps.
func _keys() -> bool:
	var ok := true
	var jump := _keycodes("jump")
	var shoot := _keycodes("shoot")
	ok = _check(not jump.has(KEY_SPACE) and jump.has(KEY_W) and jump.has(KEY_UP), "jump is W and Up, not Space") and ok
	ok = _check(shoot == [KEY_SPACE], "shoot is Space") and ok
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
	ok = _check(not abilities.gun_unlocked and is_equal_approx(abilities.gun_cooldown, 0.2) and is_equal_approx(abilities.gun_shot_speed, 260.0), "the gun starts locked, at a shot every 0.2 s and 260 px/s") and ok
	ok = _check(abilities.apply(Upgrades.get_def("gun"), true) and abilities.gun_unlocked and not abilities.apply(Upgrades.get_def("gun"), true), "the gun upgrade unlocks it once") and ok
	ok = _check(abilities.apply(Upgrades.get_def("gun_cooldown"), 0.1) and not abilities.apply(Upgrades.get_def("gun_cooldown"), 0.15) and is_equal_approx(abilities.gun_cooldown, 0.1), "a cooldown upgrade only lowers it") and ok
	ok = _check(abilities.apply(Upgrades.get_def("gun_shot_speed"), 300.0) and not abilities.apply(Upgrades.get_def("gun_shot_speed"), 100.0) and is_equal_approx(abilities.gun_shot_speed, 300.0), "a shot speed upgrade only raises it") and ok
	var back := Abilities.from_dict(abilities.to_dict())
	ok = _check(back.gun_unlocked and is_equal_approx(back.gun_cooldown, 0.1) and is_equal_approx(back.gun_shot_speed, 300.0), "the gun round-trips through a save") and ok
	var old := Abilities.from_dict({})
	ok = _check(not old.gun_unlocked and is_equal_approx(old.gun_cooldown, 0.2), "and an old save loads it locked") and ok
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


## Plays on until the gun has no shot in flight, or `limit` ticks have passed.
func _wait(gun: Node, limit: int) -> void:
	for i in limit:
		await physics_frame
		if gun.shots.is_empty():
			return


## Waits out the cooldown, fires, and waits for the shot to land.
func _fire_again(gun: Node) -> void:
	for i in 60:
		if gun.cooldown_left <= 0.0:
			break
		await physics_frame
	gun.fire()
	await _wait(gun, 60)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
