extends SceneTree

## The 3TM in room 4: with no tokens it says how full it is, with some it takes
## them one at a time, remembers them, and on the third gives Imprint, after
## which it does nothing. The fill and the upgrade survive a save.

const TEMP := "user://machine_test.json"


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
	ok = _check(world.warp_to("4"), "warp to room 4, which has the 3TM") and ok
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	var machine := _machine(room)
	ok = _check(machine != null and machine.filled == 0 and not machine.spent, "room 4 shows an empty 3TM") and ok
	ok = _check(machine.rect().size == Vector2(30, 30) and room.world_rects().size() == room.info.solids.size(), "it is a 3 x 3 cell thing and not solid") and ok

	# With nothing to give, touching it says how full it is.
	await _touch(player, room)
	var toast: Label = world.get_node("Toast").get_child(0)
	ok = _check(toast.visible and "0 of 3" in toast.text and not world.is_busy(), "touched with no tokens it says how full it is, and nothing else happens (%s)" % toast.text) and ok

	# Two tokens go in, one at a time, with something flying to each slot.
	state.tokens = 2
	state.tokens_changed.emit()
	var flew := 0
	var froze := false
	var frames := 0
	await physics_frame
	while world.is_busy() and frames < 900:
		froze = froze or not player.input_enabled
		for child in world.get_children():
			if child is FlyingToken:
				flew = maxi(flew, 1)
		await physics_frame
		frames += 1
	ok = _check(froze and flew == 1, "the player is frozen and a token flies while the machine works") and ok
	ok = _check(machine.filled == 2 and state.tokens == 0 and state.machines.get("r4_3tm") == 2, "two slots fill and two tokens are spent (%d filled, %d carried, %s)" % [machine.filled, state.tokens, state.machines]) and ok
	ok = _check(not state.abilities.imprint_unlocked and player.input_enabled and not world.is_busy(), "two tokens give nothing yet, and the player is free") and ok

	# The third token fills the last slot and the machine gives Imprint.
	state.tokens = 1
	state.tokens_changed.emit()
	await physics_frame
	frames = 0
	var sparked := false
	while world.is_busy() and frames < 900:
		for child in world.get_children():
			if child is FlyingToken and child._spark:
				sparked = true
		await physics_frame
		frames += 1
	ok = _check(machine.spent and machine.filled == 3 and state.tokens == 0, "the third token fills it") and ok
	ok = _check(state.abilities.imprint_unlocked, "and gives Imprint") and ok
	ok = _check(sparked, "with a spark that comes back to the player") and ok
	ok = _check(toast.visible and "Imprint" in toast.text, "and a line says what it was (%s)" % toast.text) and ok
	ok = _check(player.input_enabled and not world.is_busy(), "the player is free again") and ok
	ok = _check(FileAccess.file_exists(TEMP), "and the game saved") and ok

	# A spent machine does nothing, and does not take a token.
	state.tokens = 1
	state.tokens_changed.emit()
	await _frames_idle(world, 40)
	ok = _check(state.tokens == 1 and not world.is_busy(), "a spent 3TM leaves the token with the player") and ok

	# Resume from the save: the machine is spent and Imprint is still there.
	world.queue_free()
	await process_frame
	state.reset()
	world = await _world()
	ok = _check(state.abilities.imprint_unlocked and state.machines.get("r4_3tm") == 3, "starting again keeps Imprint and the machine's fill (%s)" % [state.machines]) and ok
	world.warp_to("4")
	machine = _machine(world.current)
	ok = _check(machine != null and machine.spent, "and room 4 builds the 3TM already spent") and ok

	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	print("MACHINE %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Walks the player in from the right until they touch the machine, then stops.
func _touch(player: Player, room: Room) -> void:
	player.place(room.position + Grid.cell_center(Vector2i(13, 16)), room.world_rects())
	player.scripted_x = -1.0
	for i in 120:
		await physics_frame
		if _machine(room).rect().intersects(player.body_rect()):
			break
	player.scripted_x = 0.0
	await physics_frame
	await physics_frame


func _frames_idle(world: Node, count: int) -> void:
	for i in count:
		await physics_frame


func _machine(room: Room) -> TokenMachine:
	for child in room.get_children():
		if child is TokenMachine:
			return child
	return null


func _world() -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	return world


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
