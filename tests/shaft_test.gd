extends SceneTree

## The real player goes down the shaft from room 3 to room 4 and climbs back
## up, so up and down doors keep their place and their speed and land the
## player on their feet.


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
	print("SHAFT %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


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
