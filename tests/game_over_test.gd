extends SceneTree

## Game over: a death with no pips fades to black, shows "Game over" and waits
## for the keys that dismiss the power popup (nothing counts in the first
## moments, other keys do nothing, and Escape does not also open the pause
## menu), then the save room appears. A death with a pip
## left shows nothing. The centred "Game Saved" line is checked in
## save_room_test.


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
	var over: GameOver = world.game_over
	player.scripted = true
	ok = _check(not over.visible and not over.active, "the screen is not up in play") and ok

	# With a pip, a death is the shatter and a respawn, with no screen.
	state.health = 2
	state.max_health = 2
	world._die()
	await create_timer(0.9).timeout
	ok = _check(not over.visible and state.health == 1 and not world.is_busy(), "dying with a pip left shows no Game Over") and ok

	# With none, the screen comes up and waits.
	state.health = 0
	world._die()
	ok = _check(not over.visible, "it waits for the shatter first") and ok
	var up := await _until(func() -> bool: return over.visible and over._waiting, 4.0)
	ok = _check(up, "dying with no pips fades to black and waits") and ok
	ok = _check(over.active and world.is_busy() and not player.visible and world.current.info.id == "5", "the world is held in the room they died in") and ok
	ok = _check(is_equal_approx(over._black.modulate.a, 1.0) and is_equal_approx(over._title.modulate.a, 1.0) and over._title.text == "GAME OVER", "the screen is black, with GAME OVER") and ok
	ok = _check(over._prompt.text == "Enter / click to continue", "and tells them what to press") and ok

	# Nothing counts in the first moments, and a key that is not a dismissal never does.
	over._input(_key(KEY_SPACE))
	over._input(_key(KEY_ESCAPE))
	ok = _check(over.visible and over._waiting and world.current.info.id == "5", "Space and Escape are ignored in the first moments") and ok
	ok = _check(not world.pause_menu.opened and not world.pause_menu._pending, "and that Escape did not reach the pause menu") and ok
	await create_timer(GameOver.MIN_SHOW + 0.1).timeout
	over._input(_key(KEY_A))
	over._input(_key(KEY_TAB))
	ok = _check(over._waiting, "other keys do nothing, later or not") and ok
	over._input(_key(KEY_ESCAPE))
	ok = _check(not over._waiting and not over.active, "Escape continues") and ok
	await create_timer(0.1).timeout
	ok = _check(world.current.info.id == "s1", "to the save room (%s)" % world.current.info.id) and ok
	ok = _check(not world.pause_menu.opened and not world.pause_menu._pending, "without opening the pause menu") and ok
	var gone := await _until(func() -> bool: return not over.visible and not world.is_busy(), 4.0)
	ok = _check(gone and player.input_enabled and player.visible, "the black fades away and the player has control") and ok

	# Enter continues too, and so does the keypad's.
	for key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_W, KEY_UP]:
		world.warp_to("5")
		await process_frame
		state.health = 0
		world._die()
		await _until(func() -> bool: return over.visible and over._waiting, 4.0)
		await create_timer(GameOver.MIN_SHOW + 0.1).timeout
		over._input(_key(key))
		await create_timer(0.1).timeout
		ok = _check(world.current.info.id == "s1", "key %s continues" % OS.get_keycode_string(key)) and ok
		await _until(func() -> bool: return not over.visible and not world.is_busy(), 4.0)

	# A left click does too, and a right click does not.
	world.warp_to("5")
	await process_frame
	state.health = 0
	world._die()
	await _until(func() -> bool: return over.visible and over._waiting, 4.0)
	await create_timer(GameOver.MIN_SHOW + 0.1).timeout
	over._input(_click(MOUSE_BUTTON_RIGHT))
	ok = _check(over._waiting, "a right click does nothing") and ok
	over._input(_click(MOUSE_BUTTON_LEFT))
	await create_timer(0.1).timeout
	ok = _check(world.current.info.id == "s1", "a left click continues") and ok
	await _until(func() -> bool: return not over.visible and not world.is_busy(), 4.0)

	# The tests' hook continues at once.
	over.scripted = true
	world.warp_to("5")
	await process_frame
	state.health = 0
	world._die()
	var skipped := await _until(func() -> bool: return world.current.info.id == "s1", 4.0)
	ok = _check(skipped, "a scripted screen continues by itself") and ok

	# clear drops it at once.
	over.scripted = false
	over.open()
	over.clear()
	ok = _check(not over.visible and not over.active, "clear drops the screen") and ok

	world.queue_free()
	await process_frame
	state.reset()
	print("GAMEOVER %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _click(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## Waits for `done`, up to `limit` seconds. Returns whether it came true.
func _until(done: Callable, limit: float) -> bool:
	var begun := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - begun) / 1000.0 < limit:
		if done.call():
			return true
		await process_frame
	return done.call()


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
