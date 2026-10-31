extends SceneTree

## Real panel events, pause ownership, draft application, and optional native
## screenshots. Headless runs never read or write the user's loadout store.

var _ok := true


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var world: Node = load("res://src/world/world.tscn").instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	var panel: Node = world.get_node("DevPanel")
	var state: Node = root.get_node("GameState")
	var session: Node = root.get_node("DevSession")
	world.player.scripted = true
	_press(panel, KEY_F2)
	_check(panel.opened and paused and world.modal_owner == "dev", "F2 opens a paused panel")
	var imprint_switch: CheckButton = panel._fields["imprint_unlocked"]
	_check(not imprint_switch.button_pressed and imprint_switch.text == "Off", "locked Imprint displays Off when the panel opens")
	imprint_switch.button_pressed = true
	_check(imprint_switch.text == "On", "enabling Imprint updates the label to On")
	imprint_switch.button_pressed = false
	_check(imprint_switch.text == "Off", "disabling Imprint updates the label to Off")
	_check(panel._rooms.item_count == root.get_node("WorldData").rooms.size(), "room picker initially lists every implemented room")
	var selected: PackedInt32Array = panel._rooms.get_selected_items()
	_check(selected.size() == 1 and panel._rooms.get_item_text(selected[0]) == "7", "current room is selected without filtering out other rooms")
	var save_index := -1
	for index in panel._rooms.item_count:
		if panel._rooms.get_item_text(index) == "s1":
			save_index = index
	if save_index >= 0:
		panel._rooms.item_selected.emit(save_index)
	_check(panel._room.text == "s1" and panel._rooms.item_count == root.get_node("WorldData").rooms.size(), "selecting a listed room chooses it without hiding the list")
	panel._filter_rooms("s")
	var save_rooms: Array = root.get_node("WorldData").rooms.keys().filter(func(id: String) -> bool: return id.contains("s"))
	_check(panel._rooms.item_count == save_rooms.size(), "typing still filters save rooms")
	panel._filter_rooms("")
	panel._tabs.current_tab = 1
	for index in 100:
		panel._rooms.add_item("test_room_%d" % index)
	for frame in 4:
		await process_frame
	var last_room: Rect2 = panel._rooms.get_item_rect(panel._rooms.item_count - 1)
	_check(last_room.end.y <= panel._rooms.size.y and not panel._rooms.get_v_scroll_bar().visible, "long room list grows to fit every row without an inner scrollbar")
	var page: ScrollContainer = panel._tabs.get_child(1)
	_check(page.get_v_scroll_bar().visible, "Rooms uses its single outer scrollbar for the long page")
	panel._tabs.current_tab = 2
	for index in 100:
		panel._names.add_item("test_loadout_%d" % index)
	for frame in 4:
		await process_frame
	var last_loadout: Rect2 = panel._names.get_item_rect(panel._names.item_count - 1)
	_check(last_loadout.end.y <= panel._names.size.y and not panel._names.get_v_scroll_bar().visible, "long loadout list also has no inner scrollbar")
	panel._refresh_names()
	panel._filter_rooms("")
	panel._tabs.current_tab = 0
	var tick: int = world.current.tick
	await create_timer(0.05).timeout
	_check(world.current.tick == tick, "moving platform clock stops while editing")
	_check(not world.acquire_modal("map"), "map cannot take the dev panel's pause")
	world.release_modal("map")
	_check(paused, "map close cannot unpause dev panel")
	panel._fields["imprint_unlocked"].button_pressed = true
	panel._fields["imprint_width"].text = "5"
	panel._fields["tokens"].text = "3"
	_check(panel._apply() and state.tokens == 3 and state.abilities.imprint_width == 5 and state.abilities.imprint_unlocked, "panel applies a complete valid draft")
	state.tokens = 1
	panel.close_panel()
	panel.open_panel()
	panel._fields["imprint_duration"].text = "7.5"
	_check(panel._apply() and state.tokens == 1 and session.loadout["tokens"] == 3, "editing an unrelated field does not overwrite retry resources")
	world.imprint.scripted = true
	world.imprint.scripted_cell = Vector2i(3, 8)
	world.imprint.refresh_preview()
	panel._fields["imprint_width"].text = str(DevCatalog.MAX_INTEGER)
	_check(panel._apply() and world.imprint.preview_state() == "unavailable", "extreme width invalidates the old preview before drawing")
	world.imprint.refresh_preview()
	_check(world.imprint.preview_reason() == "outside", "extreme width is refused without overflow or per-cell work")
	panel._fields["imprint_width"].text = "5"
	panel._apply()
	_check(panel._fields.has("imprint_cooldown"), "the panel has a cooldown field")
	panel._fields["imprint_cooldown"].text = "0.2"
	_check(panel._apply() and is_equal_approx(state.abilities.imprint_cooldown, 0.2), "panel applies a cooldown")
	var cooldown_control: Dictionary = DevCatalog.controls()["imprint_cooldown"]
	panel._fields["imprint_cooldown"].text = "0"
	for i in 3:
		panel._nudge("imprint_cooldown", 1, cooldown_control)
	_check(panel._fields["imprint_cooldown"].text == "0.3", "three presses of + give 0.3, not float noise (%s)" % panel._fields["imprint_cooldown"].text)
	for i in 5:
		panel._nudge("imprint_cooldown", -1, cooldown_control)
	_check(float(panel._fields["imprint_cooldown"].text) == 0.0, "and − stops at 0 (%s)" % panel._fields["imprint_cooldown"].text)
	panel._apply()
	_check(is_zero_approx(state.abilities.imprint_cooldown), "and the cooldown can be turned off again")
	_check(panel._classic != null and not panel._classic.button_pressed and not session.classic_imprint, "the Classic Imprint switch is on the Player tab, off")
	panel._classic.button_pressed = true
	_check(session.classic_imprint, "turning it on reaches the session")
	_check(session.status_line().contains("classic imprint"), "and the pause menu's status line says so (%s)" % session.status_line())
	_check(not panel._draft().has("classic_imprint") and not panel._draft().get("abilities", {}).has("classic_imprint"), "it is not part of the draft")
	panel._fields["imprint_cooldown"].text = "0"
	_check(panel._apply() and session.classic_imprint, "Apply does not change it")
	panel._fields["health"].text = "bad"
	panel._fields["tokens"].text = "2"
	_check(not panel._apply() and state.tokens == 1, "invalid panel draft is atomic")
	_press(panel, KEY_ESCAPE)
	_check(not panel.opened and not paused and state.tokens == 1, "Escape discards unapplied fields")
	_check(session.classic_imprint, "and does not change the Classic switch")
	panel.open_panel()
	_check(panel._classic.button_pressed, "the switch shows its state when the panel opens again")
	panel._classic.button_pressed = false
	_check(not session.classic_imprint, "and turns off again")
	_check(not session.status_line().contains("classic"), "with the status line clear of it")
	_check(panel._token_marks != null and not panel._token_marks.button_pressed and not session.token_marks, "the token marks switch is on the Player tab, off")
	panel._token_marks.button_pressed = true
	_check(session.token_marks and session.status_line().contains("token marks"), "turning it on reaches the session, and the status line")
	_check(not panel._draft().has("token_marks") and not panel._draft().get("abilities", {}).has("token_marks"), "it is not part of the draft")
	panel._fields["imprint_cooldown"].text = "0"
	_check(panel._apply() and session.token_marks, "Apply does not change it")
	_press(panel, KEY_ESCAPE)
	session.token_marks = false
	panel.open_panel()
	_check(not panel._token_marks.button_pressed, "the switch shows the session's state when the panel opens again, not its own")
	panel._token_marks.button_pressed = true
	panel._token_marks.button_pressed = false
	_check(not session.token_marks, "and turns off again")
	# The pixel font has ASCII only; anything else draws as a box with its code point in it (U+2212, the
	# Unicode minus, showed as "2212" on the - buttons).
	var odd: Array[String] = []
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Button or node is Label:
			for ch in String(node.text):
				if ch.unicode_at(0) > 126:
					odd.append("%s in '%s'" % [ch, node.text])
	_check(odd.is_empty(), "every button and label in the dev panel is in the pixel font's ASCII (%s)" % [odd])
	_check(panel._wall != null and panel._wall.text == "2", "the wall strength field is on the Player tab, at 2")
	panel._wall.text_submitted.emit("4")
	_check(session.wall_strength() == 4 and panel._wall.text == "4", "typing a number sets the strength")
	panel._wall.text_submitted.emit("0")
	_check(session.wall_strength() == 4 and panel._wall.text == "4", "an invalid number is refused and the field shows the real value")
	panel._wall.text_submitted.emit("x")
	_check(session.wall_strength() == 4, "and so is text")
	session.wall_strength_override = 0
	panel._wall.text = "3"
	panel.close_panel()
	world._busy = true
	_press(panel, KEY_F2)
	_check(not panel.opened and panel._pending == 0, "panel defers opening during an animation")
	_press(panel, KEY_F2)
	_check(panel._pending == -1, "second F2 cancels pending opening")
	_press(panel, KEY_F2)
	world._busy = false
	await process_frame
	await process_frame
	_check(panel.opened, "pending panel opens after the animation")
	panel.close_panel()
	var map: Node = world.get_node("MapOverlay")
	map._set_open(true)
	panel.open_panel()
	_check(not panel.opened and panel._pending >= 0, "dev panel waits for held map to close")
	map._set_open(false)
	for i in 15:
		await process_frame
	_check(panel.opened and paused and world.modal_owner == "dev", "pause transfers to the panel after map closes")
	panel.close_panel()
	Input.action_press("jump")
	_check(world.gameplay_input_blocked(), "held gameplay input is suppressed after closing")
	# A direction held through the panel does not turn the player either.
	world.player.scripted = false
	world.player.facing = 1
	Input.action_press("move_left")
	for i in 3:
		await physics_frame
	_check(world.player.facing == 1, "a held direction does not turn the player while input is suppressed")
	Input.action_release("move_left")
	Input.action_release("jump")
	_check(not world.gameplay_input_blocked(), "gameplay resumes once held keys are released")
	Input.action_press("move_left")
	for i in 2:
		await physics_frame
	Input.action_release("move_left")
	_check(world.player.facing == -1, "and a fresh press turns them")
	world.player.facing = 1
	world.player.scripted = true
	_press(panel, KEY_F4)
	_check(panel.opened and panel._tabs.current_tab == 1, "F4 focuses room selection")
	panel._room.text = "999"
	panel._start(false)
	_check(world.current.info.id == "7" and panel._status.text.contains("No such room"), "invalid room selection leaves test unchanged")
	panel._room.text = "s1"
	panel._start(false)
	await process_frame
	await process_frame
	world = _current_world()
	panel = world.get_node("DevPanel")
	world.player.scripted = true
	_check(world.current.info.id == "s1" and not paused and state.tokens == 3, "room picker starts a save-room test and replenishes the loadout")
	panel.open_panel()
	await process_frame
	await process_frame
	_check(panel._window.size.x <= 312 and panel._window.size.y <= 160, "panel fits the native viewport")
	if DisplayServer.get_name() != "headless":
		for tab in 3:
			panel._tabs.current_tab = tab
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/dev-panel-%d.png" % tab)
	panel.close_panel()
	world.free()
	print("DEV UI %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


func _current_world() -> Node:
	for child in root.get_children():
		if child.has_method("warp_to"):
			return child
	return null


func _press(panel: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	panel._input(event)


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	_ok = condition and _ok
