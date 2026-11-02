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
	# Room 2 holds its doors shut until its token is taken. Start with it taken.
	root.get_node("GameState").flags["token:r2_token"] = true
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "2"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var camera: Camera2D = world.get_node("Camera2D")
	player.scripted = true

	# Room 2 has a door in its right wall, at the end of a ledge.
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(29, 8)), room.world_rects())
	var ok := true
	player.scripted_x = 1.0
	ok = _check(await _until(world, "3"), "walking right through room 2's door arrives in room 3") and ok
	player.scripted_x = 0.0
	var landed := Grid.world_to_cell(player.global_position - world.current.position)
	ok = _check(_standing(world) and landed.y == 8 and landed.x <= 8, "the player crosses level onto room 3's entrance ledge (%s)" % landed) and ok
	ok = _check(camera.position.x >= 800.0 - 0.5, "the camera has slid to room 3 (%s)" % camera.position) and ok
	player.scripted_x = 0.0
	await _frames(90)
	ok = _check(_room() == "3", "the player is not thrown back out of room 3") and ok

	# Back off room 3's entrance ledge, up onto room 2's.
	player.scripted_x = -1.0
	for i in 480:
		await physics_frame
		if _room() == "2":
			break
	player.scripted_x = 0.0
	ok = _check(await _until(world, "2"), "walking left through room 3's door arrives back in room 2") and ok
	ok = _check(_standing(world), "the player is standing on floor inside room 2") and ok
	player.scripted_x = 0.0
	await _frames(90)
	ok = _check(_room() == "2", "the player is not thrown back out of room 2") and ok
	ok = await _airborne_transfers(world) and ok
	root.get_node("GameState").reset()
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


## Start in an authored doorway in midair and let the engine detect the
## crossing. Check each edge with no power, an exhausted jump and a partly
## consumed three-jump budget; the camera slide must freeze jump timers.
func _airborne_transfers(world: Node) -> bool:
	var ok := true
	var player: Player = world.player
	var state := root.get_node("GameState")
	for edge in ["right", "up", "down"]:
		for budget in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 1)]:
			var source: String = {"right": "2", "up": "4", "down": "3"}[edge]
			world.warp_to(source)
			var room: Room = world.current
			var door: Door
			for candidate in room.info.exits:
				if candidate.edge == edge:
					door = candidate
					break
			state.abilities.air_jumps = budget.x
			player.air_jumps = budget.x
			player.place(room.position + door.trigger_rect().get_center(), room.world_rects())
			player.velocity = Vector2(90, -120) if edge == "right" else Vector2(0, -220 if edge == "up" else 120)
			player._state.air_left = budget.y
			player._state.grounded = false
			player._state.coyote = 0.0
			player._state.buffer = 0.04
			player._state.launched = true
			player._state.cut = true
			player.scripted_x = 1.0 if edge == "right" else 0.0
			player.scripted_jump_held = true
			for i in 8:
				await physics_frame
				if world.is_busy():
					break
			ok = _check(world._pending != null, "%s airborne crossing starts with %s jumps" % [edge, budget]) and ok
			if world._pending == null:
				continue
			var captured := player.capture_transfer()
			ok = _check(captured.air_left == budget.y and captured.cut and captured.launched, "door entry preserves budget and jump cut/launch") and ok
			ok = _check(player.riding() == -1 and player._state.floor_rect == Rect2(), "door entry clears room-local contacts") and ok
			ok = _check(await _until(world, door.dest_id), "%s transition completes" % edge) and ok
			ok = _check(player._state.air_left == budget.y and player._state.buffer == captured.buffer and player._state.coyote == captured.coyote and player._state.cut, "slide freezes timers and held jump cannot refresh the budget") and ok
			ok = _check(player.velocity == world._carried, "mapped door velocity survives the slide") and ok
	player.scripted_jump_held = false
	player.scripted_x = 0.0
	return ok
