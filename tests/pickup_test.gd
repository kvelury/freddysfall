extends SceneTree

## The Imprint pickup in room 2: the player walks into it, it is taken, the game
## saves, and a new game started from that save has Imprint and no pickup.

const TEMP := "user://pickup_test.json"


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
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = true
	DirAccess.remove_absolute(TEMP)
	state.reset()

	var world: Node = await _world()
	ok = _check(world.current.info.id == "1", "with no save the game starts in the start room") and ok
	ok = _check(world.warp_to("2"), "warp to room 2, which has the pickup") and ok
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	ok = _check(_pickups(room).size() == 1, "room 2 shows its pickup") and ok
	ok = _check(not state.abilities.imprint_unlocked, "the player starts without Imprint") and ok

	# Stand on the platform, left of the pickup, and walk into it.
	player.place(room.position + Grid.cell_center(Vector2i(8, 8)), room.world_rects())
	player.scripted_x = 1.0
	var taken := false
	for i in 120:
		await physics_frame
		if state.has_flag("pickup:r2_imprint"):
			taken = true
			break
	player.scripted_x = 0.0
	ok = _check(taken, "walking into it takes it") and ok
	ok = _check(state.abilities.imprint_unlocked, "and unlocks Imprint") and ok
	await physics_frame
	await physics_frame
	ok = _check(_pickups(room).is_empty(), "the pickup is gone from the room") and ok
	ok = _check(world.get_node("Toast").get_child(0).visible, "and a line says what it was") and ok
	ok = _check(FileAccess.file_exists(TEMP), "and the game saved") and ok

	# A fresh game from the save.
	world.queue_free()
	await process_frame
	state.reset()
	world = await _world()
	room = world.current
	ok = _check(room.info.id == "2", "starting again resumes in room 2 (%s)" % room.info.id) and ok
	ok = _check(state.abilities.imprint_unlocked, "with Imprint still unlocked") and ok
	ok = _check(_pickups(room).is_empty(), "and the pickup stays gone") and ok
	ok = _check(Rect2(room.position, room.info.pixel_size).has_point(world.get_node("Player").global_position), "the player is inside the room") and ok

	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	print("PICKUP %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _world() -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	return world


func _pickups(room: Room) -> Array[Node]:
	return room.get_children().filter(func(c: Node) -> bool: return c is Pickup and not c.is_queued_for_deletion())


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
