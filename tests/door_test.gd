extends SceneTree

## The real player walks through a door and back. Touching a door has to change
## rooms exactly once, put the player on their feet inside the next room, and
## not bounce them straight back.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "2"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var camera: Camera2D = world.get_node("Camera2D")
	player.scripted = true

	# Room 2 has a floor-level door in its right wall. Start a few cells short.
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(24, 16)), room.world_rects())
	var ok := true
	player.scripted_x = 1.0
	ok = _check(await _until(world, "3"), "walking right through room 2's door arrives in room 3") and ok
	ok = _check(_standing(world), "the player is standing on floor inside room 3") and ok
	ok = _check(camera.position.x >= 800.0 - 0.5, "the camera has slid to room 3 (%s)" % camera.position) and ok
	player.scripted_x = 0.0
	await _frames(90)
	ok = _check(_room() == "3", "the player is not thrown back out of room 3") and ok

	player.scripted_x = -1.0
	ok = _check(await _until(world, "2"), "walking left through room 3's door arrives back in room 2") and ok
	ok = _check(_standing(world), "the player is standing on floor inside room 2") and ok
	player.scripted_x = 0.0
	await _frames(90)
	ok = _check(_room() == "2", "the player is not thrown back out of room 2") and ok
	print("DOOR %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Waits until the world is in `id` with control handed back, up to 8 seconds.
func _until(world: Node, id: String) -> bool:
	var player: Player = world.get_node("Player")
	for i in 480:
		await physics_frame
		if _room() == id and player.input_enabled:
			return true
	return false


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _standing(world: Node) -> bool:
	var player: Player = world.get_node("Player")
	var info: RoomInfo = root.get_node("WorldData").get_room(_room())
	var cell := Grid.world_to_cell(player.global_position - Vector2(info.grid_pos) * Grid.SCREEN_SIZE)
	return player.is_on_floor() and not info.is_solid(cell.x, cell.y)


func _room() -> String:
	return String(root.get_node("GameState").current_room_id)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
