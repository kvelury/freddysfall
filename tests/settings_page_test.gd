extends TestCase

## The Controls page of Settings: choosing a row and slot, capturing a key or a
## button, the swap note, cancelling, the Reset row and Back. Events go straight
## to the page's `_input`, as the menu tests do.


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	await process_frame
	var bindings: Node = root.get_node("InputBindings")
	bindings.enabled = false
	bindings.reset("keyboard")
	bindings.reset("controller")
	var was_device: String = Controls.device
	Controls.device = "keyboard"
	var page := SettingsPage.new()
	root.add_child(page)
	await process_frame
	var ok := true

	ok = check(page.kind() == "keyboard" and page._selected == 0, "it opens on the keyboard tab, on the device row") and ok
	_press(page, KEY_RIGHT)
	ok = check(page.kind() == "controller", "Right on the device row switches to the controller tab") and ok
	_press(page, KEY_LEFT)
	for i in 5:
		_press(page, KEY_DOWN)
	ok = check(page._actions[page._selected - 1] == "jump", "Down walks to Jump (%s)" % page._actions[page._selected - 1]) and ok

	_press(page, KEY_ENTER)
	ok = check(page._capturing, "Enter starts a capture") and ok
	_press(page, KEY_ESCAPE)
	ok = check(not page._capturing and bindings.get_bindings("jump", "keyboard").size() == 1 and bindings.get_bindings("jump", "keyboard")[0]["code"] == KEY_SPACE, "Esc cancels it and changes nothing") and ok
	_press(page, KEY_ENTER)
	_press(page, KEY_F2)
	ok = check(page._capturing, "a function key is ignored while capturing") and ok
	_pad(page, JOY_BUTTON_Y)
	ok = check(page._capturing, "a button is ignored on the keyboard tab") and ok
	_press(page, KEY_Z)
	ok = check(not page._capturing and bindings.get_bindings("jump", "keyboard")[0]["code"] == KEY_Z, "a key becomes the binding") and ok

	# A clash says so.
	_press(page, KEY_ENTER)
	_press(page, KEY_X)
	ok = check(page._status.begins_with("Swapped with") and bindings.get_bindings("lash", "keyboard")[0]["code"] == KEY_Z, "a key another action has swaps (%s)" % page._status) and ok

	# Second slot.
	_press(page, KEY_RIGHT)
	ok = check(page._slot == 1, "Right moves to the second slot") and ok
	_press(page, KEY_ENTER)
	_press(page, KEY_C)
	ok = check(bindings.get_bindings("jump", "keyboard").size() == 2, "and fills it") and ok

	# Controller tab: a button, and the cancel buttons.
	_press(page, KEY_UP)
	_press(page, KEY_UP)
	_press(page, KEY_UP)
	_press(page, KEY_UP)
	_press(page, KEY_UP)
	ok = check(page._selected == 0, "Up walks back to the device row") and ok
	_press(page, KEY_RIGHT)
	for i in 5:
		_press(page, KEY_DOWN)
	_press(page, KEY_LEFT)
	_press(page, KEY_ENTER)
	_pad(page, JOY_BUTTON_START)
	ok = check(not page._capturing and bindings.get_bindings("jump", "controller")[0]["index"] == JOY_BUTTON_A, "Start cancels a controller capture") and ok
	_press(page, KEY_ENTER)
	_press(page, KEY_Q)
	ok = check(page._capturing, "a key is ignored on the controller tab") and ok
	_pad(page, JOY_BUTTON_B)
	ok = check(not page._capturing and bindings.get_bindings("jump", "controller")[0]["index"] == JOY_BUTTON_B, "a button becomes the binding") and ok

	# Reset restores the tab shown and nothing else.
	for i in 4:
		_press(page, KEY_DOWN)
	ok = check(page._selected == page._count - 2, "Down reaches Reset") and ok
	_press(page, KEY_ENTER)
	ok = check(bindings.is_default("controller") and not bindings.is_default("keyboard"), "Reset restores the controller tab only") and ok

	# Back.
	var backed := [false]
	page.back_requested.connect(func() -> void: backed[0] = true)
	_press(page, KEY_DOWN)
	_press(page, KEY_ENTER)
	ok = check(backed[0], "the Back row leaves") and ok
	backed[0] = false
	_press(page, KEY_ESCAPE)
	ok = check(backed[0], "and so does Escape") and ok

	page.hide()
	_press(page, KEY_DOWN)
	ok = check(page._selected == page._count - 1, "a hidden page ignores keys") and ok

	bindings.reset("keyboard")
	bindings.reset("controller")
	Controls.device = was_device
	page.free()
	finish("SETTINGS PAGE", ok)


func _press(page: SettingsPage, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	page._input(event)


func _pad(page: SettingsPage, index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = true
	page._input(event)
