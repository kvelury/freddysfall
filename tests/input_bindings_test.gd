extends TestCase

## Controller and keyboard bindings: the defaults, remapping (swaps, refusals),
## saving and loading `user://controls.json`, the labels each pad family shows,
## and that the player's controls are not part of the game save.

const PATH := "user://test_input_bindings.json"


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	await process_frame
	var bindings: Node = root.get_node("InputBindings")
	bindings.enabled = false
	bindings.reset("keyboard")
	bindings.reset("controller")
	var ok := _defaults()
	ok = _rebind(bindings) and ok
	ok = _persistence(bindings) and ok
	ok = _labels(bindings) and ok
	ok = _save_isolation(bindings) and ok
	bindings.path = "user://controls.json"
	bindings.enabled = true
	bindings.reset("keyboard")
	bindings.reset("controller")
	finish("INPUT BINDINGS", ok)


func _button(index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = true
	return event


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


## Whether `action` fires on `event` (an input of the same kind and number).
func _has(action: String, event: InputEvent) -> bool:
	for each in InputMap.action_get_events(action):
		if each.is_match(event, true):
			return true
	return false


func _defaults() -> bool:
	var ok := true
	var table := {
		"move_left": [_axis(0, -1.0), _button(JOY_BUTTON_DPAD_LEFT)],
		"move_right": [_axis(0, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)],
		"look_up": [_axis(1, -1.0), _button(JOY_BUTTON_DPAD_UP)],
		"look_down": [_axis(1, 1.0), _button(JOY_BUTTON_DPAD_DOWN)],
		"jump": [_button(JOY_BUTTON_A)],
		"lash": [_button(JOY_BUTTON_X), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		"map": [_button(JOY_BUTTON_LEFT_SHOULDER)],
		"pause": [_button(JOY_BUTTON_START)],
		"map_zoom_in": [_axis(1, -1.0), _button(JOY_BUTTON_DPAD_UP)],
		"map_zoom_out": [_axis(1, 1.0), _button(JOY_BUTTON_DPAD_DOWN)],
	}
	for action: String in table:
		for event: InputEvent in table[action]:
			ok = check(_has(action, event), "%s is on the controller by default (%s)" % [action, event.as_text()]) and ok
	ok = check(_has("jump", _key(KEY_SPACE)) and _has("lash", _key(KEY_X)), "the keyboard keeps Space and X") and ok
	ok = check(_has("pause", _key(KEY_ESCAPE)) and _has("pause", _key(KEY_P)), "pause keeps Esc and P") and ok
	ok = check(not _has("lash", _button(JOY_BUTTON_A)) and not _has("jump", _button(JOY_BUTTON_X)), "jump is not on the left face button and lash is not on the bottom one") and ok
	ok = check(InputMap.action_get_deadzone("look_up") > 0.65 and InputMap.action_get_deadzone("move_left") == 0.5, "look up needs a firmer push than moving (%.2f)" % InputMap.action_get_deadzone("look_up")) and ok
	var bindings: Node = root.get_node("InputBindings")
	ok = check(bindings.is_default("keyboard") and bindings.is_default("controller"), "nothing is changed at the start") and ok
	return ok


func _rebind(bindings: Node) -> bool:
	var ok := true
	var key := {"t": "key", "code": int(KEY_Z)}
	var result: Dictionary = bindings.rebind("jump", 0, key)
	ok = check(result["ok"] and _has("jump", _key(KEY_Z)) and not _has("jump", _key(KEY_SPACE)), "a key rebinds a slot and the InputMap follows") and ok
	ok = check(bindings.get_bindings("jump", "keyboard") == [key], "and it is what the action reports") and ok

	# A second slot is added by binding one past the last.
	result = bindings.rebind("jump", 1, {"t": "key", "code": int(KEY_C)})
	ok = check(result["ok"] and bindings.get_bindings("jump", "keyboard").size() == 2, "a second binding is added") and ok

	# An input another action has: the two swap, and neither is left bare.
	result = bindings.rebind("lash", 0, {"t": "key", "code": int(KEY_Z)})
	ok = check(result["ok"] and String(result["note"]).begins_with("Swapped with"), "a clash swaps (%s)" % result["note"]) and ok
	ok = check(_has("lash", _key(KEY_Z)) and _has("jump", _key(KEY_X)) and not _has("jump", _key(KEY_Z)), "Lash has Z and Jump has the X it gave up") and ok
	# Adding a second binding that another action holds with a spare takes it from them.
	result = bindings.rebind("lash", 1, {"t": "key", "code": int(KEY_C)})
	ok = check(result["ok"] and String(result["note"]).begins_with("Taken from") and bindings.get_bindings("jump", "keyboard").size() == 1, "an extra binding takes from an action that has two (%s)" % result["note"]) and ok
	# ... but never from one that has only that.
	result = bindings.rebind("move_left", 1, {"t": "key", "code": int(KEY_SPACE)})
	result = bindings.rebind("move_left", 0, {"t": "key", "code": int(KEY_Z)})
	ok = check(result["ok"], "moving a key across slots works (%s)" % result["note"]) and ok

	# Things that cannot be bound.
	for event: InputEvent in [_key(KEY_ESCAPE), _key(KEY_F2), _key(KEY_SHIFT), _button(JOY_BUTTON_START), _button(JOY_BUTTON_BACK), _axis(0, 0.3), _axis(JOY_AXIS_TRIGGER_LEFT, -1.0)]:
		ok = check(Controls.binding_from_event(event).is_empty(), "%s cannot be bound" % event.as_text()) and ok
	ok = check(not bindings.rebind("jump", 0, {"t": "key", "code": int(KEY_ESCAPE)}).is_empty() and bindings.rebind("jump", 5, key)["ok"] == false, "a bad slot is refused") and ok
	ok = check(not _has("jump", _key(KEY_ESCAPE)), "and Esc is not jump") and ok
	var released := _key(KEY_Q)
	released.pressed = false
	ok = check(Controls.binding_from_event(released).is_empty(), "a key coming up is not a binding") and ok

	# Controller bindings are their own list.
	result = bindings.rebind("jump", 0, {"t": "button", "index": int(JOY_BUTTON_Y)})
	ok = check(result["ok"] and _has("jump", _button(JOY_BUTTON_Y)) and not _has("jump", _button(JOY_BUTTON_A)), "a button rebinds the controller slot") and ok
	ok = check(_has("jump", _key(KEY_X)), "and the keyboard's are untouched") and ok
	result = bindings.rebind("move_right", 0, {"t": "axis", "axis": int(JOY_AXIS_RIGHT_X), "sign": 1})
	ok = check(result["ok"] and _has("move_right", _axis(JOY_AXIS_RIGHT_X, 1.0)), "a stick direction can be bound") and ok
	# Map zoom follows look up and down.
	bindings.rebind("look_up", 0, {"t": "key", "code": int(KEY_I)})
	ok = check(_has("map_zoom_in", _key(KEY_I)), "map zoom follows look up") and ok

	bindings.reset("keyboard")
	ok = check(_has("jump", _key(KEY_SPACE)) and not _has("jump", _key(KEY_Z)) and _has("jump", _button(JOY_BUTTON_Y)), "reset puts one device back and leaves the other") and ok
	bindings.reset("controller")
	ok = check(bindings.is_default("keyboard") and bindings.is_default("controller") and _has("jump", _button(JOY_BUTTON_A)) and _has("map_zoom_in", _key(KEY_W)), "reset both is the default again") and ok
	return ok


func _persistence(bindings: Node) -> bool:
	var ok := true
	bindings.path = PATH
	bindings.enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	bindings.rebind("jump", 0, {"t": "key", "code": int(KEY_Z)})
	bindings.rebind("lash", 1, {"t": "button", "index": int(JOY_BUTTON_Y)})
	ok = check(FileAccess.file_exists(PATH), "a change is written") and ok
	var saved := [bindings.get_bindings("jump", "keyboard"), bindings.get_bindings("lash", "controller")]
	bindings.reset("keyboard")
	bindings.reset("controller")
	bindings.enabled = false
	bindings.enabled = true
	# Reset saved the defaults; write the changes again and load them back.
	bindings.rebind("jump", 0, {"t": "key", "code": int(KEY_Z)})
	bindings.rebind("lash", 1, {"t": "button", "index": int(JOY_BUTTON_Y)})
	bindings._current = bindings._copy(bindings._defaults)
	bindings.load_file()
	ok = check([bindings.get_bindings("jump", "keyboard"), bindings.get_bindings("lash", "controller")] == saved, "a saved change comes back on load") and ok
	ok = check(_has("jump", _key(KEY_Z)) and _has("lash", _button(JOY_BUTTON_Y)), "and is in the InputMap") and ok

	# A file that is not usable leaves the defaults.
	for text in ["not json", "[]", '{"version": 99, "bindings": {}}', '{"version": 1, "bindings": {"jump": {"keyboard": [{"t": "key", "code": 4194305}]}}}', '{"version": 1, "bindings": {"jump": {"keyboard": [{"t": "bogus"}]}}}', '{"version": 1, "bindings": {"jump": {"keyboard": []}}}']:
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		bindings.load_file()
		ok = check(bindings.is_default("keyboard") and bindings.is_default("controller"), "a bad file (%s) leaves the defaults" % text.left(28)) and ok
	# One good action in a file with a bad one is still read.
	var mixed := FileAccess.open(PATH, FileAccess.WRITE)
	mixed.store_string('{"version": 1, "bindings": {"jump": {"keyboard": [{"t": "key", "code": %d}]}, "lash": {"keyboard": [{"t": "bogus"}]}}}' % int(KEY_Z))
	mixed.close()
	bindings.load_file()
	ok = check(_has("jump", _key(KEY_Z)) and _has("lash", _key(KEY_X)), "a good action is kept and a bad one falls back") and ok
	# A hand-edited file giving one key to two actions is repaired.
	var clash := FileAccess.open(PATH, FileAccess.WRITE)
	clash.store_string('{"version": 1, "bindings": {"jump": {"keyboard": [{"t": "key", "code": %d}]}, "lash": {"keyboard": [{"t": "key", "code": %d}]}}}' % [int(KEY_Z), int(KEY_Z)])
	clash.close()
	bindings.load_file()
	ok = check(not (_has("jump", _key(KEY_Z)) and _has("lash", _key(KEY_Z))), "one key never fires two actions") and ok

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	bindings.enabled = false
	bindings.load_file()
	bindings.reset("keyboard")
	bindings.reset("controller")
	return ok


func _labels(_bindings: Node) -> bool:
	var ok := true
	ok = check(PadLabels.family("Xbox 360 Controller") == "xbox" and PadLabels.family("PS5 Controller") == "playstation" and PadLabels.family("Nintendo Switch Pro Controller") == "nintendo" and PadLabels.family("") == "xbox", "the pad family comes from its name") and ok
	ok = check(PadLabels.button("xbox", JOY_BUTTON_A) == "A" and PadLabels.button("playstation", JOY_BUTTON_A) == "Cross" and PadLabels.button("nintendo", JOY_BUTTON_A) == "B", "the bottom button is A, Cross or B") and ok
	ok = check(PadLabels.button("xbox", JOY_BUTTON_LEFT_SHOULDER) == "LB" and PadLabels.button("playstation", JOY_BUTTON_RIGHT_SHOULDER) == "R1", "shoulders are LB / R1") and ok
	var was_device: String = Controls.device
	var was_name: String = Controls.pad_name
	Controls.device = "controller"
	Controls.pad_name = "PS5 Controller"
	ok = check(Controls.key_groups(Controls.get_row("jump")) == [["Cross"]], "jump shows Cross on a PlayStation pad (%s)" % [Controls.key_groups(Controls.get_row("jump"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("lash")) == [["Square"], ["R1"]], "lash shows Square / R1 (%s)" % [Controls.key_groups(Controls.get_row("lash"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("map")) == [["L1"]], "map shows L1") and ok
	ok = check(Controls.key_groups(Controls.get_row("move")) == [["L-Stick"], ["Left", "Right"]], "move is the stick and the D-pad (%s)" % [Controls.key_groups(Controls.get_row("move"))]) and ok
	ok = check(Controls.key_groups(Controls.get_row("imprint")).is_empty(), "the mouse-only row has nothing on a controller") and ok
	ok = check(Controls.press_any() == "Press any button to continue", "popups ask for a button") and ok
	Controls.pad_name = "Xbox Controller"
	ok = check(Controls.key_groups(Controls.get_row("jump")) == [["A"]] and Controls.key_groups(Controls.get_row("jump"), "keyboard") == [["Space"]], "an Xbox pad shows A, and the keyboard can still be asked for") and ok
	Controls.device = "keyboard"
	ok = check(Controls.press_any() == "Press any key to continue", "and the keyboard says key") and ok
	# Stick movement never dismisses a popup; a button does.
	ok = check(not Controls.dismisses(_axis(0, 1.0)) and Controls.dismisses(_button(JOY_BUTTON_A)), "a stick does not dismiss a popup and a button does") and ok
	Controls.device = was_device
	Controls.pad_name = was_name
	return ok


func _save_isolation(bindings: Node) -> bool:
	var ok := true
	bindings.path = PATH
	bindings.enabled = true
	bindings.rebind("jump", 0, {"t": "key", "code": int(KEY_Z)})
	var save: Node = root.get_node("Save")
	var was_path: String = save.path
	var was_enabled: bool = save.enabled
	save.path = "user://test_input_bindings_save.json"
	save.enabled = true
	save.erase()
	root.get_node("GameState").reset()
	ok = check(_has("jump", _key(KEY_Z)), "erasing the save and a new game keep the player's controls") and ok
	save.path = was_path
	save.enabled = was_enabled
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	bindings.enabled = false
	bindings.reset("keyboard")
	return ok
