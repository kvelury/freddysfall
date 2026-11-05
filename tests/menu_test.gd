extends TestCase

## The main menu, the Controls page, the pause menu and the power popup.


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var ok := _controls_data()
	ok = await _main_menu() and ok
	ok = await _pause_menu() and ok
	ok = await _popup() and ok
	ok = await _pad_and_rebound_keys() and ok
	finish("MENU", ok)


func _controls_data() -> bool:
	var ok := check(Controls.problems().is_empty(), "the controls file is clean (%s)" % [Controls.problems()])
	ok = check(Upgrades.problems().is_empty(), "the upgrades file is clean (%s)" % [Upgrades.problems()]) and ok
	for id in Upgrades.all():
		for row_id in Upgrades.get_def(id).controls:
			ok = check(not Controls.get_row(row_id).is_empty(), "upgrade %s shows controls row %s" % [id, row_id]) and ok
	ok = check(Controls.key_groups(Controls.get_row("move")) == [["A", "D"], ["Left", "Right"]], "move is A D / Left Right (%s)" % [Controls.key_groups(Controls.get_row("move"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("pause")) == [["Esc"], ["P"]], "pause is Esc / P (%s)" % [Controls.key_groups(Controls.get_row("pause"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("imprint")) == [["MouseLeft"]], "imprint is the left mouse button") and ok
	ok = check(_ids(Controls.visible_rows(null)) == ["move", "jump", "look_up", "look_down", "map", "map_zoom", "pause"], "with no game only the base rows show (%s)" % [_ids(Controls.visible_rows(null))]) and ok
	var abilities := Abilities.new()
	abilities.air_jumps = 1
	abilities.tongue_unlocked = true
	ok = check(_ids(Controls.visible_rows(abilities)) == ["move", "jump", "double_jump", "look_up", "look_down", "lash", "lash_up", "map", "map_zoom", "pause"], "owned powers add their rows (%s)" % [_ids(Controls.visible_rows(abilities))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("lash_up")) == [["W", "X"], ["Up", "X"]], "lash up is W + X / Up + X (%s)" % [Controls.key_groups(Controls.get_row("lash_up"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("jump")) == [["Space"]], "jump is Space") and ok
	return ok


func _main_menu() -> bool:
	var save := root.get_node("Save")
	var was_enabled: bool = save.enabled
	var was_path: String = save.path
	# MainMenu is reached through load(): naming it here would compile it before the autoloads exist.
	(load("res://src/ui/main_menu.gd") as GDScript).set("_booted", true)
	var ok := true

	save.enabled = false
	var menu := await _menu()
	ok = check(menu._main_list.item_texts() == ["Start Game", "Settings"], "no save: Start Game and Settings (%s)" % [menu._main_list.item_texts()]) and ok
	ok = check(menu._main_list.selected() == 0, "the first item is selected") and ok
	menu._main_list.get_child(1).pressed.emit()
	ok = check(menu._settings_page.visible and not menu._main_page.visible, "Settings opens its page") and ok
	menu._settings_list.get_child(0).pressed.emit()
	ok = check(menu._controls_page.visible and not menu._settings_page.visible, "Controls opens the remapping page") and ok
	menu._remap.back_requested.emit()
	ok = check(menu._settings_page.visible and not menu._controls_page.visible, "Back from Controls returns to Settings") and ok
	menu._settings_list.get_child(1).pressed.emit()
	ok = check(menu._main_page.visible and not menu._settings_page.visible, "Back returns to the menu") and ok
	menu.free()

	save.enabled = true
	save.path = "user://menu_test_save.json"
	var file := FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	menu = await _menu()
	ok = check(menu._main_list.item_texts() == ["Continue", "New Game", "Settings"], "a save: Continue, New Game, Settings (%s)" % [menu._main_list.item_texts()]) and ok
	menu._main_list.get_child(1).pressed.emit()
	ok = check(menu._confirm_page.visible and menu._confirm_list.selected() == 0, "New Game asks first, with No selected") and ok
	menu._unhandled_input(_key(KEY_ESCAPE))
	ok = check(menu._main_page.visible and not menu._confirm_page.visible, "Escape answers No") and ok
	menu.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save.path))
	save.enabled = was_enabled
	save.path = was_path

	save.enabled = false
	menu = await _menu()
	menu._main_list.get_child(0).pressed.emit()
	await process_frame
	await process_frame
	var world := _world_node()
	ok = check(world != null and world.from_menu, "Start Game builds a world from the menu") and ok
	if world != null:
		world.free()
	save.enabled = was_enabled
	return ok


func _pause_menu() -> bool:
	var ok := true
	var world := await _world("2")
	var menu = world.pause_menu
	menu._unhandled_input(_key(KEY_ESCAPE))
	ok = check(menu.opened and paused and world.modal_owner == "pause", "Esc pauses the game") and ok
	menu._unhandled_input(_key(KEY_ESCAPE))
	ok = check(not menu.opened and not paused and world.modal_owner.is_empty(), "Esc again resumes") and ok
	menu._unhandled_input(_key(KEY_P))
	ok = check(menu.opened and paused, "P pauses too") and ok
	menu._list.get_child(1).pressed.emit()
	ok = check(menu._screen == "settings", "Settings opens its page") and ok
	menu._settings_list.get_child(0).pressed.emit()
	ok = check(menu._screen == "controls" and menu._remap.is_visible_in_tree(), "Controls shows the remapping page") and ok
	menu._unhandled_input(_key(KEY_P))
	ok = check(menu.opened and menu._screen == "settings", "P on the Controls page goes back to Settings") and ok
	menu._unhandled_input(_key(KEY_P))
	ok = check(menu.opened and menu._screen == "list", "and P on Settings goes back to the list") and ok
	menu._list.get_child(0).pressed.emit()
	ok = check(not menu.opened and not paused, "Resume resumes") and ok

	world._set_mode(2)
	menu._unhandled_input(_key(KEY_ESCAPE))
	ok = check(not menu.opened and menu._pending, "during an animation the press waits") and ok
	world._set_mode(0)
	menu._process(0.0)
	ok = check(menu.opened, "it opens once the animation is over") and ok
	menu.close()

	var panel := world.get_node("DevPanel")
	panel.open_panel()
	menu._unhandled_input(_key(KEY_P))
	ok = check(panel.opened and not menu.opened, "P does not open over the dev panel") and ok
	panel.close_panel()

	# Dev tools is in the list when dev is available (a debug build is), and the
	# status line is there only during a test.
	var session := root.get_node("DevSession")
	session.mode = session.Mode.NORMAL
	menu.open()
	ok = check(menu._list.item_texts() == ["Resume", "Settings", "Dev tools", "Main menu"], "dev available: Dev tools is in the list (%s)" % [menu._list.item_texts()]) and ok
	ok = check(not menu._status.visible, "and there is no status line in a normal game") and ok
	menu.close()
	session.available = false
	menu.open()
	ok = check(menu._list.item_texts() == ["Resume", "Settings", "Main menu"], "dev not available: no Dev tools (%s)" % [menu._list.item_texts()]) and ok
	menu.close()
	session.available = true
	session.mode = session.Mode.DEV_TEST
	session.bypass = true
	menu.open()
	ok = check(menu._status.visible and menu._status.text == "Dev: not saving · doors open", "in a test the status line shows (%s)" % menu._status.text) and ok
	menu._list.get_child(2).pressed.emit()
	var dev_panel := world.get_node("DevPanel")
	ok = check(dev_panel.opened and not menu.opened and world.modal_owner == "dev", "Dev tools closes the menu and opens the dev panel") and ok
	dev_panel.close_panel()
	ok = check(not paused and world.modal_owner.is_empty(), "and closing the panel gives the game back") and ok
	session.mode = session.Mode.NORMAL
	session.bypass = false

	_gs().abilities.air_jumps = 1
	menu.open()
	menu._list.get_child(menu._list.item_texts().find("Main menu")).pressed.emit()
	await process_frame
	await process_frame
	var main_menu := _menu_node()
	ok = check(main_menu != null and not paused and root.get_node("DevSession").mode == 0 and _gs().abilities.air_jumps == 0, "Main menu leaves a clean normal game") and ok
	if main_menu != null:
		main_menu.free()
	return ok


func _popup() -> bool:
	var ok := true
	var world := await _world("2")
	var popup = world.power_popup
	_gs().grant("double_jump", "1")
	await physics_frame
	await physics_frame
	ok = check(popup.opened and paused, "a new power opens the popup and pauses") and ok
	ok = check(not world.toast._label.visible, "the toast stays quiet for it") and ok
	popup._input(_key(KEY_ENTER))
	ok = check(popup.opened, "input in the first moments does not dismiss") and ok
	await create_timer(popup.MIN_SHOW + 0.1, true, false, true).timeout
	popup._input(_click(MOUSE_BUTTON_LEFT))
	popup._input(_key(KEY_F3))
	ok = check(popup.opened, "a mouse click and a dev key do not dismiss it") and ok
	ok = check(popup._prompt.text == "Press any key to continue", "and it says any key does") and ok
	popup._input(_key(KEY_X))
	ok = check(not popup.opened and not paused, "any other key (X) dismisses it and the game runs") and ok

	world._announce(_gs().grant("tongue_cooldown", "0.1"))
	await physics_frame
	await physics_frame
	ok = check(not popup.opened and world.toast._label.visible and world.toast._label.text == "Lash Cooldown +1", "an upgrade with no controls is a toast (%s)" % world.toast._label.text) and ok

	var session := root.get_node("DevSession")
	ok = check(session.enter(world).is_empty(), "the dev session starts") and ok
	var error: String = session.apply(world, {"abilities": {"air_jumps": 2}})
	await physics_frame
	await physics_frame
	ok = check(error.is_empty() and _gs().abilities.air_jumps == 2 and not popup.opened, "a dev edit never shows a popup (%s)" % error) and ok
	world.free()
	return ok


func _menu() -> Node:
	var menu: Node = (load("res://src/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	return menu


func _world(override: String) -> Node:
	_gs().reset()
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = override
	root.add_child(world)
	await process_frame
	return world


func _world_node() -> Node:
	for child in root.get_children():
		if child.has_method("leave_to_menu"):
			return child
	return null


func _menu_node() -> Node:
	for child in root.get_children():
		if child.has_method("_start"):
			return child
	return null


func _click(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _ids(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> String: return row["id"])


func _gs() -> Node:
	return root.get_node("GameState")


func _pad(index: int, device := 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index as JoyButton
	event.pressed = true
	return event


## A picks and B goes back, on any pad, on every screen of both menus; and keys
## the player has given to look up and down do not take Enter and Space from the
## menus.
func _pad_and_rebound_keys() -> bool:
	var ok := true
	for device in [0, 1]:
		ok = check(_pad(JOY_BUTTON_A, device).is_action_pressed("ui_accept"), "pad %d: A is accept" % device) and ok
		ok = check(_pad(JOY_BUTTON_B, device).is_action_pressed("ui_cancel"), "pad %d: B is cancel" % device) and ok

	var save := root.get_node("Save")
	var was_enabled: bool = save.enabled
	save.enabled = false
	var menu := await _menu()
	menu._main_list.get_child(1).pressed.emit()
	menu._unhandled_input(_pad(JOY_BUTTON_B))
	ok = check(menu._main_page.visible and not menu._settings_page.visible, "B goes back from Settings to the main menu") and ok
	menu._main_list.get_child(1).pressed.emit()
	menu._settings_list.get_child(0).pressed.emit()
	menu._remap._input(_pad(JOY_BUTTON_B))
	ok = check(menu._settings_page.visible and not menu._controls_page.visible, "B goes back from Controls to Settings") and ok
	menu.free()
	save.enabled = was_enabled

	var world := await _world("2")
	var pause = world.pause_menu
	pause._unhandled_input(_pad(JOY_BUTTON_B))
	ok = check(not pause.opened and not paused, "B in play does not open the pause menu") and ok
	pause._unhandled_input(_pad(JOY_BUTTON_START))
	ok = check(pause.opened and paused, "Start pauses") and ok
	pause._list.get_child(1).pressed.emit()
	pause._settings_list.get_child(0).pressed.emit()
	ok = check(pause._screen == "controls", "Controls is showing") and ok
	pause._remap._input(_pad(JOY_BUTTON_B))
	ok = check(pause.opened and pause._screen == "settings", "B on Controls goes to Settings, once") and ok
	pause._unhandled_input(_pad(JOY_BUTTON_B))
	ok = check(pause.opened and pause._screen == "list", "B on Settings goes to the pause list") and ok
	pause._unhandled_input(_pad(JOY_BUTTON_B))
	ok = check(not pause.opened and not paused, "B on the pause list resumes") and ok
	pause._unhandled_input(_pad(JOY_BUTTON_START, 1))
	ok = check(pause.opened, "Start on a second pad pauses") and ok
	pause.close()

	# Look up on Enter and look down on Space: both are allowed, and the menus
	# still take them as accept.
	var bindings := root.get_node("InputBindings")
	var was_bindings: bool = bindings.enabled
	bindings.enabled = false
	bindings.rebind("look_up", 0, {"t": "key", "code": int(KEY_ENTER)})
	bindings.rebind("look_down", 0, {"t": "key", "code": int(KEY_SPACE)})
	pause.open()
	pause._list.focus_item(1)
	pause._list._input(_key(KEY_ENTER))
	ok = check(pause._list.selected() == 1, "Enter (look up) does not move a menu selection") and ok
	pause._list._input(_key(KEY_SPACE))
	ok = check(pause._list.selected() == 1, "Space (look down) does not move it either") and ok
	pause._list._input(_key(KEY_DOWN))
	ok = check(pause._list.selected() == 2, "the arrow keys still do") and ok
	pause.close()
	bindings.reset("keyboard")
	bindings.enabled = was_bindings
	world.free()
	return ok
