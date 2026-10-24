extends SceneTree

## Save rooms. s1 holds its door shut until the player has used its save
## machine, a split sphere: walking into its zone hops the player into the
## middle, it closes and spins, the game saves, a line says so, the door opens,
## and it pops them out on the far side in about a second. It works once each
## time the room is entered, and stays shut after. Put back inside it (by a
## reload, or by dying with no health) the player is popped out to the right
## without a save. Dying with a pip spends it and keeps today's safe-floor
## respawn; with no save room entered yet, death goes to the start room.

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
	ok = _check(machine != null and machine.openness == 1.0 and not machine.used, "the room has its save machine, standing open") and ok
	ok = _check(state.save_room == "s1", "entering a save room makes it the save room") and ok
	ok = _check(room.locked and _blocks(room) == 1, "its door is blocked until the machine is used (%d blocks)" % _blocks(room)) and ok
	ok = _check(not FileAccess.file_exists(TEMP), "nothing has been saved yet") and ok

	# Enter the zone at the platform's left end.
	var door_rects := room.world_rects().size()
	var left := room.position + Grid.cell_center(Vector2i(14, 8))
	var right := room.position + Grid.cell_center(Vector2i(18, 8))
	var run := await _save_from(player, room, left)
	ok = _check(run["held"], "entering the machine's zone takes control from the player") and ok
	ok = _check(run["released"] and run["pause"] >= 0.9 and run["pause"] < 1.3, "and gives it back about a second later (%.2f s)" % run["pause"]) and ok
	ok = _check(run["hidden"] and run["shut"], "the player is inside while it is shut round them") and ok
	ok = _check(run["top"] < machine.centre().y - 3.0, "they hop in on an arc (highest point %.1f, the middle is %.1f)" % [run["top"], machine.centre().y]) and ok
	await _frames(12)
	ok = _check(machine.used and machine.openness == 0.0, "the machine is used, and closes behind them") and ok
	ok = _check(player.visible and player.is_on_floor(), "the player is back, standing") and ok
	ok = _check(player.global_position.distance_to(machine.global_position + Vector2(20, 0)) < 1.0, "popped out on the far side, to the right of where they came in from the left (%s)" % player.global_position) and ok
	ok = _check(state.has_flag("save:s1_save"), "the save is remembered in the flags") and ok
	var toast: Label = world.get_node("Toast").get_child(0)
	ok = _check(toast.visible and toast.text == "Game saved", "a line says the game was saved (%s)" % toast.text) and ok
	ok = _check(not room.locked and _blocks(room) == 0, "the door opens, as room 2's does for its token") and ok
	ok = _check(player.solids.size() == door_rects - 1, "and the player no longer collides with the block (%d to %d)" % [door_rects, player.solids.size()]) and ok
	ok = _check(FileAccess.file_exists(TEMP), "the game was written to the save file") and ok
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMP))
	var spot := Grid.cell_center(room.info.save_cell())
	ok = _check(written is Dictionary and written["room"] == "s1" and written["save_room"] == "s1" and Vector2(float(written["position"][0]), float(written["position"][1])) == spot and written["flags"].has("save:s1_save"), "which resumes at the machine (%s)" % [written]) and ok

	# Once a visit: walking back through the zone leaves the player alone.
	var held := false
	player.scripted_x = -1.0
	for i in 40:
		await physics_frame
		held = held or not player.input_enabled
	player.scripted_x = 0.0
	ok = _check(not held and machine.openness == 0.0, "walking back through the zone does nothing, and the machine stays shut") and ok

	# A new visit builds it open and unused, and from the right it pops out on the left.
	world.warp_to("s1")
	room = world.current
	machine = _machine(room)
	ok = _check(machine.openness == 1.0 and not machine.used and not room.locked, "entering the room again finds it open and unused, with the door open") and ok
	run = await _save_from(player, room, right)
	ok = _check(run["held"] and run["released"] and run["pause"] >= 0.9 and run["pause"] < 1.3, "so it works again (%.2f s)" % run["pause"]) and ok
	ok = _check(player.global_position.distance_to(machine.global_position + Vector2(-20, 0)) < 1.0, "and entered from the right it pops them out on the left (%s)" % player.global_position) and ok

	# A reload resumes inside the machine, and it lets the player out.
	world.queue_free()
	await process_frame
	state.reset()
	world = await _world()
	player = world.get_node("Player")
	player.scripted = true
	room = world.current
	machine = _machine(room)
	ok = _check(room.info.id == "s1" and state.has_flag("save:s1_save"), "a reload resumes in s1 with the machine used") and ok
	ok = _check(world.is_busy() and not player.visible and machine.used and machine.openness == 0.0, "the player is inside it, shut") and ok
	var emerged := await _emerge_time(world, player)
	ok = _check(emerged >= 0.3 and emerged < 0.7, "and it opens and pops them out in under a second (%.2f s)" % emerged) and ok
	ok = _check(player.global_position.distance_to(machine.global_position + Vector2(20, 0)) < 1.0 and player.is_on_floor(), "to the right of it, standing (%s)" % player.global_position) and ok
	await _frames(12)
	ok = _check(machine.openness == 0.0 and not room.locked, "it is shut again, with the door open") and ok

	# Dying with no health goes back into the machine, and it lets the player out
	# without saving again.
	state.health = 0
	world.warp_to("5")
	DirAccess.remove_absolute(TEMP)
	ok = await _die_in_5(world, player) and ok
	room = world.current
	machine = _machine(room)
	await _frames(12)
	ok = _check(room.info.id == "s1", "dying with no health sends the player to the save room (%s)" % room.info.id) and ok
	ok = _check(player.global_position.distance_to(machine.global_position + Vector2(20, 0)) < 1.0, "popped out to the right of the machine (%s)" % player.global_position) and ok
	ok = _check(machine.used and machine.openness == 0.0 and not room.locked, "which has been used already, so it stays shut and the door open") and ok
	ok = _check(not FileAccess.file_exists(TEMP), "and nothing was saved again") and ok
	var wait := 0
	player.scripted_x = -1.0
	for i in 30:
		await physics_frame
		wait += 0 if player.input_enabled else 1
	player.scripted_x = 0.0
	ok = _check(wait == 0, "and walking back through its zone does nothing") and ok

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
	ok = _check(room.locked and _machine(room).openness == 1.0, "where the machine has not been used, so it is open and the door is shut") and ok

	# Back on a machine that was never used (the save room was only entered): it
	# saves first, then lets the player out.
	state.reset()
	state.save_room = "s1"
	world.warp_to("5")
	DirAccess.remove_absolute(TEMP)
	ok = await _die_in_5(world, player) and ok
	room = world.current
	machine = _machine(room)
	await _frames(12)
	ok = _check(room.info.id == "s1" and state.has_flag("save:s1_save") and not room.locked, "dying with the save room only entered saves in the machine and opens the door") and ok
	ok = _check(FileAccess.file_exists(TEMP) and machine.used and machine.openness == 0.0, "which writes the game and leaves it shut") and ok

	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	print("SAVEROOM %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Puts the player at `at`, inside the machine's zone, and watches the save.
## Returns when it ends: whether control was taken and given back, how long the
## player was held, whether they were hidden while it was shut, and how high
## they rose.
func _save_from(player: Player, room: Room, at: Vector2) -> Dictionary:
	var machine := _machine(room)
	var out := {"held": false, "released": false, "pause": 0.0, "hidden": false, "shut": false, "top": INF}
	player.place(at, player.solids)
	var begun := Time.get_ticks_msec()
	for i in 240:
		await physics_frame
		if not player.input_enabled:
			out["held"] = true
			out["top"] = minf(out["top"], player.global_position.y)
			if not player.visible and machine.openness == 0.0:
				out["hidden"] = true
				out["shut"] = true
		elif out["held"]:
			out["released"] = true
			break
	out["pause"] = float(Time.get_ticks_msec() - begun) / 1000.0
	return out


## How long a world just loaded with the player inside a machine takes to give
## them control, in seconds.
func _emerge_time(world: Node, player: Player) -> float:
	var begun := Time.get_ticks_msec()
	for i in 240:
		await physics_frame
		if player.input_enabled and not world.is_busy():
			break
	return float(Time.get_ticks_msec() - begun) / 1000.0


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
