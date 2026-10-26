extends SceneTree

## The real player goes down the shaft from room 3 to room 4 and climbs back
## up, so up and down doors keep their place and their speed and land the
## player on their feet. The long drop from 6 to 7 lands safely beside s2.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "3"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	player.scripted = true
	var ok := true

	# Down: walk off the floor into the hole at columns 5 to 10.
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(3, 16)), room.world_rects())
	player.scripted_x = 1.0
	ok = _check(await _until(world, "4"), "walking into room 3's floor hole arrives in room 4") and ok
	ok = _check(player.velocity.x > 60.0, "the player keeps running right through the door (%s)" % player.velocity) and ok
	player.scripted_x = 0.0
	ok = _check(await _settles(world), "the player lands on their feet in room 4") and ok

	# Up: jump straight up from the top platform into the ceiling hole at columns 5 to 10.
	room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(10, 4)), room.world_rects())
	player.scripted_x = 0.0
	for frame in 40:
		player.scripted_jump_pressed = frame == 0
		player.scripted_jump_held = frame < 30
		await physics_frame
		if _room() == "3":
			break
	ok = _check(await _until(world, "3"), "jumping into room 4's ceiling hole arrives in room 3") and ok
	ok = _check(player.velocity.y <= -Door.UP_BOOST + 0.01, "the player leaves at least the minimum rise (%s)" % player.velocity) and ok
	player.scripted_jump_held = false
	player.scripted_x = 1.0
	ok = _check(await _settles(world), "steering onto the floor, the player lands in room 3 and stays") and ok
	ok = await _merged_drop(world) and ok
	world.queue_free()
	print("SHAFT %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Cross the real shifted doorway at several positions and speeds, release
## steering, and fall to the floor. No moving-platform timing is required.
func _merged_drop(world: Node) -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	var player: Player = world.get_node("Player")
	state.health = 1
	for x in [55.0, 85.0, 125.0]:
		for vx in [-90.0, 0.0, 90.0]:
			world.warp_to("6")
			var source: Room = world.current
			player.place(source.position + Vector2(x, 170.5), source.world_rects())
			player.velocity = Vector2(vx, 100.0)
			player.scripted_x = 0.0
			var entered := await _until(world, "7")
			var landed := entered and await _settles(world)
			var local: Vector2 = player.global_position - world.current.position
			ok = _check(landed and world.current.info.id == "7" and state.health == 1 and player.riding() == -1 and is_equal_approx(local.y, 705.0) and local.x + MovementSim.HALF.x <= 150.0, "drop x %.0f, vx %.0f lands on safe floor without steering (%s, health %d)" % [x, vx, local, state.health]) and ok
			if not entered or state.health != 1:
				return false
	# The landing connects to the existing save room through its left door.
	player.scripted_x = -1.0
	ok = _check(await _until(world, "s2"), "the landing floor leads left into save room s2") and ok
	player.scripted_x = 0.0
	return ok


## Waits until the world is in `id` with control handed back, up to 8 seconds.
func _until(world: Node, id: String) -> bool:
	var player: Player = world.get_node("Player")
	for i in 480:
		await physics_frame
		if _room() == id and player.input_enabled:
			return true
	return false


## Waits for the player to rest on the floor, then checks they are not about to
## be thrown into another room.
func _settles(world: Node) -> bool:
	var player: Player = world.get_node("Player")
	var room := _room()
	for i in 240:
		await physics_frame
		if player.is_on_floor() and player.input_enabled:
			break
	for i in 60:
		await physics_frame
	return player.is_on_floor() and _room() == room


func _room() -> String:
	return String(root.get_node("GameState").current_room_id)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
