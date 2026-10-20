extends SceneTree

## Imprint in the real game: locked until it is found, placed with a click,
## solid under the player, replaced by the next one, broken by time, and gone
## when the room is left or the player dies. Uses room 5, which has spikes.


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
	state.reset()
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "5"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var tool: Node = world.get_node("Imprint")
	player.scripted = true
	tool.scripted = true
	var room: Room = world.current
	var base := room.world_rects().size()

	tool.scripted_cell = Vector2i(3, 8)
	ok = _check(not tool.place() and tool.platforms.is_empty(), "before Imprint is found, a click does nothing") and ok
	state.abilities.imprint_unlocked = true

	# Preview looks. The player is on the floor at the left.
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	await physics_frame
	tool.scripted_cell = Vector2i(6, 13)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "reachable", "a platform a hop away looks reachable (%s)" % tool.preview_state()) and ok
	tool.scripted_cell = Vector2i(10, 3)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unreachable", "one far overhead looks unreachable (%s)" % tool.preview_state()) and ok
	tool.scripted_cell = Vector2i(10, 16)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unavailable" and tool.preview_reason() == "spikes", "one on the spikes is unavailable (%s)" % tool.preview_reason()) and ok
	ok = _check(not tool.place() and tool.platforms.is_empty(), "and a click there does nothing") and ok

	# Placed by an input event, as the mouse button would.
	tool.scripted_cell = Vector2i(10, 14)
	var click := InputEventAction.new()
	click.action = "imprint"
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	await physics_frame
	ok = _check(tool.platforms.size() == 1, "the imprint action places a platform above the spikes") and ok
	ok = _check(player.solids.size() == base + 1, "and the player now collides with it (%d solids)" % player.solids.size()) and ok

	# A body dropped onto one in open air lands and stays.
	tool.scripted_cell = Vector2i(19, 13)
	ok = _check(tool.place() and tool.platforms.size() == 1, "a second click replaces the first at once") and ok
	player.global_position = room.position + Vector2(200.0, 112.0)
	player.velocity = Vector2.ZERO
	var landed := false
	for i in 120:
		await physics_frame
		if player.is_on_floor() and absf(player.global_position.y - (room.position.y + 130.0 - 5.0)) < 0.6:
			landed = true
			break
	ok = _check(landed, "the player lands on it and stands there (%s)" % player.global_position) and ok

	# Replaced at once.
	tool.scripted_cell = Vector2i(3, 6)
	player.place(room.position + Grid.cell_center(Vector2i(20, 3)), room.world_rects())
	tool.platforms.clear()
	tool.scripted_cell = Vector2i(10, 14)
	tool.place()
	tool.scripted_cell = Vector2i(3, 6)
	ok = _check(tool.place() and tool.platforms.size() == 1, "placing a second destroys the first and takes its place") and ok
	ok = _check(is_equal_approx(tool.platforms[0].rect.position.x, room.position.x + 30.0), "the one that is left is the new one") and ok
	ok = _check(player.solids.size() == base + 1, "and the player has one platform to collide with") and ok

	# Time breaks it, and the player on it falls.
	tool.platforms[0].lifetime = 0.5
	player.global_position = room.position + Vector2(35.0, 20.0)
	player.velocity = Vector2.ZERO
	for i in 20:
		await physics_frame
	ok = _check(player.is_on_floor() and player.global_position.y < room.position.y + 60.0, "the player stands on it before it breaks (%s)" % player.global_position) and ok
	for i in 40:
		await physics_frame
	ok = _check(tool.platforms.is_empty() and player.solids.size() == base, "it breaks on time and stops being solid") and ok
	var fell := false
	for i in 60:
		await physics_frame
		if player.global_position.y > room.position.y + 150.0:
			fell = true
			break
	ok = _check(fell, "and the player falls") and ok

	# Longer, from the ability.
	state.abilities.imprint_duration = 6.0
	state.abilities.imprint_width = 3
	player.place(room.position + Grid.cell_center(Vector2i(20, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(5, 5)
	tool.place()
	ok = _check(is_equal_approx(tool.platforms[0].lifetime, 6.0) and is_equal_approx(tool.platforms[0].rect.size.x, 30.0), "width and duration come from the abilities") and ok
	state.abilities.imprint_duration = Abilities.new().imprint_duration
	state.abilities.imprint_width = 2

	# Leaving the room clears it.
	ok = _check(world.warp_to("4") and tool.platforms.is_empty() and world.get_node("Player").solids.size() == world.current.world_rects().size(), "leaving a room removes the platform and its collision") and ok

	# Dying clears it.
	world.warp_to("5")
	room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(5, 8)
	tool.place()
	player.global_position = room.position + Vector2(160.0, 400.0)
	for i in 30:
		await physics_frame
	ok = _check(tool.platforms.is_empty(), "dying removes the platform") and ok

	world.queue_free()
	await process_frame
	state.reset()
	print("IMPRINTPLAY %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
