extends SceneTree

## Save rooms. s1 holds its door shut until the player has walked into its save
## machine: they are held for about a second while it lights, the game saves, a
## line says so, and the door opens. Stepping off and on saves again. Dying with
## no health sends the player back to that machine without another pause; dying
## with a pip spends it and keeps today's safe-floor respawn; with no save room
## entered yet, death goes to the start room.

const TEMP := "user://save_room_test.json"


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
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	var machine := _machine(room)
	ok = _check(room.info.id == "s1" and room.info.is_save_room(), "a new game starts in save room s1") and ok
	ok = _check(machine != null and not machine.lit, "the room has its save machine, and it is dark") and ok
	ok = _check(state.save_room == "s1", "entering a save room makes it the save room") and ok
	ok = _check(room.locked and _blocks(room) == 1, "its door is blocked until the machine is used (%d blocks)" % _blocks(room)) and ok
	ok = _check(not FileAccess.file_exists(TEMP), "nothing has been saved yet") and ok

	# Walk into the machine from the platform's left end.
	var door_rects := room.world_rects().size()
	player.place(room.position + Grid.cell_center(Vector2i(14, 8)), room.world_rects())
	await _frames(3)
	var started := Time.get_ticks_msec()
	player.scripted_x = 1.0
	var held := await _held(player)
	player.scripted_x = 0.0
	ok = _check(held, "walking into the machine takes control from the player") and ok
	var released := await _released(player)
	var pause := float(Time.get_ticks_msec() - started) / 1000.0
	ok = _check(released and pause >= 0.9 and pause < 2.0, "and gives it back about a second later (%.2f s)" % pause) and ok
	ok = _check(machine.lit, "the machine is lit") and ok
	ok = _check(state.has_flag("save:s1_save"), "the save is remembered in the flags") and ok
	var toast: Label = world.get_node("Toast").get_child(0)
	ok = _check(toast.visible and toast.text == "Game saved", "a line says the game was saved (%s)" % toast.text) and ok
	ok = _check(not room.locked and _blocks(room) == 0, "the door opens, as room 2's does for its token") and ok
	ok = _check(player.solids.size() == door_rects - 1, "and the player no longer collides with the block (%d to %d)" % [door_rects, player.solids.size()]) and ok
	ok = _check(FileAccess.file_exists(TEMP), "the game was written to the save file") and ok
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMP))
	var spot := Grid.cell_center(room.info.save_cell())
	ok = _check(written is Dictionary and written["room"] == "s1" and written["save_room"] == "s1" and Vector2(float(written["position"][0]), float(written["position"][1])) == spot and written["flags"].has("save:s1_save"), "which resumes at the machine (%s)" % [written]) and ok

	# Off and on again saves again.
	player.place(room.position + Grid.cell_center(Vector2i(14, 8)), room.world_rects())
	await _frames(3)
	player.scripted_x = 1.0
	held = await _held(player)
	player.scripted_x = 0.0
	ok = _check(held, "stepping off and back on holds the player again") and ok
	await _released(player)

	# Dying with no health goes back to the machine, without a pause.
	state.health = 0
	world.warp_to("5")
	room = world.current
	ok = await _die_in_5(world, player) and ok
	room = world.current
	ok = _check(room.info.id == "s1", "dying with no health sends the player to the save room (%s)" % room.info.id) and ok
	ok = _check(player.global_position.distance_to(room.position + spot) < 1.0, "onto the machine (%s)" % player.global_position) and ok
	await _frames(20)
	ok = _check(player.input_enabled and not world.is_busy() and _machine(room).lit, "with no pause, the machine already lit") and ok
	ok = _check(not room.locked, "and the door still open") and ok

	# Dying with a pip spends it and comes back on safe floor.
	state.health = 1
	world.warp_to("5")
	ok = await _die_in_5(world, player) and ok
	ok = _check(world.current.info.id == "5" and state.health == 0, "dying with a pip spends it and stays in the room (%s, %d health)" % [world.current.info.id, state.health]) and ok

	# No save room entered yet: the start room's start.
	state.reset()
	world.warp_to("5")
	ok = await _die_in_5(world, player) and ok
	room = world.current
	var start := Grid.cell_center(room.info.spawn_cell)
	ok = _check(room.info.id == "s1" and player.global_position.distance_to(room.position + start) < 1.0, "with no save room entered, death goes to the start (%s at %s)" % [room.info.id, player.global_position]) and ok
	ok = _check(room.locked, "where the machine has not been used, so the door is shut") and ok

	# Back on a machine that was never used (the save room was only entered):
	# it works as soon as the player is on it.
	state.reset()
	state.save_room = "s1"
	world.warp_to("5")
	ok = await _die_in_5(world, player) and ok
	room = world.current
	ok = _check(room.info.id == "s1" and room.locked, "dying with the save room only entered puts the player on its unused machine") and ok
	await _frames(5)
	ok = _check(not player.input_enabled or state.has_flag("save:s1_save"), "which saves at once") and ok
	await _released(player)
	ok = _check(state.has_flag("save:s1_save") and not room.locked, "and opens the door") and ok

	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	print("SAVEROOM %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Walks the player into room 5's spikes and waits for them to come back.
func _die_in_5(world: Node, player: Player) -> bool:
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(26, 16)), room.world_rects())
	player.scripted_x = -1.0
	var died := false
	for i in 240:
		await physics_frame
		if not player.visible:
			died = true
			break
	player.scripted_x = 0.0
	var back := false
	if died:
		for i in 240:
			await physics_frame
			if player.visible and player.input_enabled:
				back = true
				break
	return _check(died and back, "the player dies in room 5's spikes and comes back")


## Waits until the player has lost control, up to two seconds of frames.
func _held(player: Player) -> bool:
	for i in 120:
		await physics_frame
		if not player.input_enabled:
			return true
	return false


func _released(player: Player) -> bool:
	for i in 240:
		await physics_frame
		if player.input_enabled:
			return true
	return false


func _machine(room: Room) -> SaveMachine:
	for child in room.get_children():
		if child is SaveMachine:
			return child
	return null


func _blocks(room: Room) -> int:
	return room.get_children().filter(func(c: Node) -> bool: return c is Room.DoorBlock and not c.is_queued_for_deletion()).size()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _world() -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	return world


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
