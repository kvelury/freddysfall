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
	world.start_override = "8"
	root.add_child(world)
	await process_frame
	var panel: Node = world.get_node("DevPanel")
	var state: Node = root.get_node("GameState")
	var session: Node = root.get_node("DevSession")
	world.player.scripted = true
	_press(panel, KEY_F2)
	_check(panel.opened and paused and world.modal_owner == "dev", "F2 opens a paused panel")
	_check(panel._rooms.item_count == root.get_node("WorldData").rooms.size(), "room picker initially lists every implemented room")
	var selected: PackedInt32Array = panel._rooms.get_selected_items()
	_check(selected.size() == 1 and panel._rooms.get_item_text(selected[0]) == "8", "current room is selected without filtering out other rooms")
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
	panel._fields["health"].text = "bad"
	panel._fields["tokens"].text = "2"
	_check(not panel._apply() and state.tokens == 1, "invalid panel draft is atomic")
	_press(panel, KEY_ESCAPE)
	_check(not panel.opened and not paused and state.tokens == 1, "Escape discards unapplied fields")
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
	Input.action_release("jump")
	_check(not world.gameplay_input_blocked(), "gameplay resumes once held keys are released")
	_press(panel, KEY_F4)
	_check(panel.opened and panel._tabs.current_tab == 1, "F4 focuses room selection")
	panel._room.text = "999"
	panel._start(false)
	_check(world.current.info.id == "8" and panel._status.text.contains("No such room"), "invalid room selection leaves test unchanged")
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
