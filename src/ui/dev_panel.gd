extends CanvasLayer

## Paused playtest controls. Widgets edit a draft; only the session controller
## can commit it, travel, or restore progression.

var opened := false
var _pending := -1
var _window: PanelContainer
var _tabs: TabContainer
var _status: Label
var _fields := {}
var _original := {}
var _full_draft := false
var _dirty := {}
var _room: LineEdit
var _rooms: ItemList
var _bypass: CheckButton
var _retry: CheckButton
var _classic: CheckButton
var _wall: LineEdit
var _names: ItemList
var _name: LineEdit
var _store := DevLoadouts.new()
var _world: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_world = get_parent()
	_build()
	if DisplayServer.get_name() != "headless":
		_store.read()
	_refresh_names()


func _process(_delta: float) -> void:
	if _pending >= 0 and not _world.is_busy() and _world.modal_owner.is_empty():
		var tab := _pending
		_pending = -1
		open_panel(tab)
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not DevSession.available or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F2:
		if opened:
			close_panel()
		elif _pending >= 0:
			_pending = -1
		else:
			open_panel()
	elif event.keycode == KEY_F4:
		open_panel(1)
	elif event.keycode == KEY_ESCAPE and (opened or _pending >= 0):
		_pending = -1
		close_panel()
	else:
		return
	get_viewport().set_input_as_handled()


func open_panel(tab := 0) -> void:
	if not DevSession.available or DevSession.replacing:
		return
	if _world.is_busy() or (not _world.modal_owner.is_empty() and _world.modal_owner != "dev"):
		_pending = tab
		return
	if not opened:
		var error := DevSession.enter(_world)
		if not error.is_empty() or not _world.acquire_modal("dev"):
			return
		opened = true
		_window.show()
		_set_fields(DevCatalog.capture(GameState.to_dict()))
		_room.text = _world.current.info.id
		_filter_rooms("")
		_bypass.set_pressed_no_signal(DevSession.bypass)
		_retry.set_pressed_no_signal(DevSession.retry_on_death)
		_classic.set_pressed_no_signal(DevSession.classic_imprint)
		_wall.text = str(DevSession.wall_strength())
		_status.text = _store.error
	_tabs.current_tab = tab
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if tab == 1:
		_room.grab_focus()
		_room.select_all()


func close_panel() -> void:
	if not opened:
		return
	opened = false
	_window.hide()
	get_viewport().gui_release_focus()
	_world.release_modal("dev")


func _build() -> void:
	_window = PanelContainer.new()
	_window.position = Vector2(4, 16)
	_window.size = Vector2(312, 160)
	_window.theme = UiTheme.build()
	_window.hide()
	add_child(_window)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	_window.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 2)
	margin.add_child(layout)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_tabs)
	_build_player(_page("Player"))
	_build_rooms(_page("Rooms"))
	_build_loadouts(_page("Loadouts"))
	_status = Label.new()
	_status.custom_minimum_size.y = 18
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	layout.add_child(_status)
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	_button(footer, "Apply", _apply)
	_button(footer, "Resume / Cancel", close_panel)
	_button(footer, "End playtest", func() -> void: _report(DevSession.end(_world)))


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	scroll.add_child(body)
	return body


func _build_player(body: VBoxContainer) -> void:
	var controls := DevCatalog.controls()
	for key in DevCatalog.RESOURCES:
		_field(body, key, DevCatalog.RESOURCES[key])
	for stat in controls:
		_field(body, stat, controls[stat])
	var row := HBoxContainer.new()
	body.add_child(row)
	_button(row, "+1 token", func() -> void: _nudge("tokens", 1, DevCatalog.RESOURCES["tokens"]))
	_button(row, "Fill 3", func() -> void: _fields["tokens"].text = "3")
	_button(row, "Empty", func() -> void: _fields["tokens"].text = "0")
	_button(row, "Clear health", func() -> void: _fields["health"].text = "0")
	_button(body, "Reset loadout to defaults", func() -> void:
		_set_fields(DevCatalog.defaults())
		_full_draft = true
		_status.text = "Defaults staged. Apply to use them."
	)
	_classic = CheckButton.new()
	_classic.text = "Classic Imprint (no shrinking)"
	_classic.toggled.connect(func(on: bool) -> void:
		_report(DevSession.set_classic_imprint(_world, on))
		_classic.set_pressed_no_signal(DevSession.classic_imprint)
	)
	body.add_child(_classic)
	var wall_row := HBoxContainer.new()
	body.add_child(wall_row)
	var wall_label := Label.new()
	wall_label.text = "Wall strength (shots)"
	wall_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_row.add_child(wall_label)
	_wall = LineEdit.new()
	_wall.custom_minimum_size.x = 62
	wall_row.add_child(_wall)
	_wall.text_submitted.connect(func(text: String) -> void: _set_wall(text))
	_button(wall_row, "−", func() -> void: _set_wall(str(DevSession.wall_strength() - 1)))
	_button(wall_row, "+", func() -> void: _set_wall(str(DevSession.wall_strength() + 1)))
	_wall.text = str(DevSession.wall_strength())


## Applies the wall strength typed or nudged. It takes effect at once, since it
## is a session setting and not part of the staged loadout.
func _set_wall(text: String) -> void:
	if not text.is_valid_int():
		_report("Wall strength is a whole number from 1 to %d." % DevSession.MAX_WALL_STRENGTH)
	else:
		_report(DevSession.set_wall_strength(_world, text.to_int()), "Wall strength set.")
	_wall.text = str(DevSession.wall_strength())


func _field(body: VBoxContainer, key: String, control: Dictionary) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var label := Label.new()
	label.text = control["name"] + (" (" + control["unit"] + ")" if control.has("unit") else "")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if control["type"] == "bool":
		var check := CheckButton.new()
		check.text = "On"
		row.add_child(check)
		check.toggled.connect(func(on: bool) -> void:
			check.text = "On" if on else "Off"
			_dirty[key] = true
		)
		_fields[key] = check
	elif control["type"] == "effects":
		var effects := {}
		for effect in control.get("implemented", []):
			var check := CheckButton.new()
			check.text = String(effect).capitalize()
			row.add_child(check)
			check.toggled.connect(func(_on: bool) -> void: _dirty[key] = true)
			effects[effect] = check
		_fields[key] = effects
		for effect in control.get("planned", []):
			var note := Label.new()
			note.text = "%s: Not implemented" % String(effect).capitalize()
			row.add_child(note)
	elif control["type"] == "unsupported":
		var note := Label.new()
		note.text = control["reason"]
		row.add_child(note)
	else:
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = 62
		row.add_child(edit)
		edit.text_changed.connect(func(_text: String) -> void: _dirty[key] = true)
		_fields[key] = edit
		_button(row, "−", func() -> void: _nudge(key, -1, control))
		_button(row, "+", func() -> void: _nudge(key, 1, control))


func _nudge(key: String, direction: int, control: Dictionary) -> void:
	var edit: LineEdit = _fields[key]
	if not edit.text.is_valid_float():
		return
	var value := float(edit.text) + float(direction) * float(control.get("step", 1))
	value = clampf(value, float(control.get("min", 0)), float(control.get("max", DevCatalog.MAX_INTEGER)))
	edit.text = str(int(value)) if control["type"] == "int" else str(value)


func _build_rooms(body: VBoxContainer) -> void:
	_room = LineEdit.new()
	_room.placeholder_text = "Room ID (including s1), then Enter"
	_room.text_changed.connect(_filter_rooms)
	_room.text_submitted.connect(func(_text: String) -> void: _start(false))
	body.add_child(_room)
	_rooms = ItemList.new()
	_rooms.auto_height = true
	_rooms.custom_minimum_size.y = 36
	_rooms.item_selected.connect(func(index: int) -> void: _room.text = _rooms.get_item_text(index))
	_rooms.item_activated.connect(func(index: int) -> void:
		_room.text = _rooms.get_item_text(index)
		_start(false)
	)
	body.add_child(_rooms)
	var row := HBoxContainer.new()
	body.add_child(row)
	_button(row, "Start test", func() -> void: _start(false))
	_button(row, "Start fresh test", func() -> void: _start(true))
	_button(row, "Retry test", func() -> void: _report(DevSession.retry(_world)))
	_bypass = CheckButton.new()
	_bypass.text = "Bypass door requirements"
	_bypass.toggled.connect(func(on: bool) -> void:
		_report(DevSession.set_bypass(_world, on))
		_bypass.set_pressed_no_signal(DevSession.bypass)
	)
	body.add_child(_bypass)
	_retry = CheckButton.new()
	_retry.text = "Retry original test on death"
	_retry.toggled.connect(func(on: bool) -> void:
		_report(DevSession.set_retry_on_death(_world, on))
		_retry.set_pressed_no_signal(DevSession.retry_on_death)
	)
	body.add_child(_retry)


func _filter_rooms(query: String) -> void:
	_rooms.clear()
	var search := query.strip_edges().to_lower()
	var ids: Array = WorldData.rooms.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for id in ids:
		if search.is_empty() or String(id).contains(search):
			_rooms.add_item(id)
			if String(id) == _room.text.strip_edges().to_lower():
				_rooms.select(_rooms.item_count - 1)


func _start(fresh: bool) -> void:
	var id := _room.text.strip_edges().to_lower()
	if not WorldData.rooms.has(id):
		_status.text = "No such room: %s" % id
		return
	if _apply():
		_report(DevSession.start(_world, id, fresh))


func _set_fields(loadout: Dictionary) -> void:
	var flat: Dictionary = loadout["abilities"].duplicate(true)
	for key in DevCatalog.RESOURCES:
		flat[key] = loadout[key]
	for key in _fields:
		var field = _fields[key]
		if field is LineEdit:
			field.text = str(flat[key])
		elif field is CheckButton:
			field.set_pressed_no_signal(bool(flat[key]))
			field.text = "On" if field.button_pressed else "Off"
		elif field is Dictionary:
			for effect in field:
				field[effect].set_pressed_no_signal(flat[key].has(effect))
	_original = flat.duplicate(true)
	_full_draft = false
	_dirty.clear()


func _draft() -> Dictionary:
	var candidate := DevCatalog.defaults()
	var controls := DevCatalog.controls()
	controls.merge(DevCatalog.RESOURCES)
	for key in _fields:
		var control: Dictionary = controls[key]
		var field = _fields[key]
		var value: Variant
		match control["type"]:
			"bool":
				value = field.button_pressed
			"effects":
				value = []
				for effect in field:
					if field[effect].button_pressed:
						value.append(effect)
			_:
				var text: String = field.text
				if not text.is_valid_float():
					return {"error": "%s: Enter a number." % control["name"]}
				value = text.to_float()
		if DevCatalog.RESOURCES.has(key):
			candidate[key] = value
		else:
			candidate["abilities"][key] = value
	return {"error": DevCatalog.validate(candidate), "loadout": candidate}


func _apply() -> bool:
	var draft := _draft()
	if not draft["error"].is_empty():
		_status.text = draft["error"]
		return false
	var values: Dictionary = draft["loadout"]
	var patch := {"abilities": {}}
	for stat in values["abilities"]:
		if _full_draft or _dirty.has(stat) or values["abilities"][stat] != _original.get(stat):
			patch["abilities"][stat] = values["abilities"][stat]
	for key in DevCatalog.RESOURCES:
		if _full_draft or _dirty.has(key) or values[key] != _original.get(key):
			patch[key] = values[key]
	var error := DevSession.apply(_world, patch)
	_report(error, "Applied. Resume when ready.")
	if error.is_empty():
		_set_fields(DevCatalog.capture(GameState.to_dict()))
	return error.is_empty()


func _build_loadouts(body: VBoxContainer) -> void:
	_names = ItemList.new()
	_names.auto_height = true
	_names.custom_minimum_size.y = 42
	_names.item_selected.connect(_select_loadout)
	body.add_child(_names)
	_name = LineEdit.new()
	_name.placeholder_text = "Loadout name"
	body.add_child(_name)
	var row := HBoxContainer.new()
	body.add_child(row)
	_button(row, "Save new", func() -> void: _save_loadout(false))
	_button(row, "Update", func() -> void: _save_loadout(true))
	_button(row, "Rename", func() -> void:
		_report(_store.rename(_selected_name(), _name.text), "Renamed.")
		_refresh_names()
	)
	_button(row, "Delete", func() -> void:
		_report(_store.remove(_selected_name()), "Deleted.")
		_refresh_names()
	)
	var note := Label.new()
	note.text = "Powers, tokens, health only.\nSelect, then Apply."
	body.add_child(note)


func _save_loadout(update: bool) -> void:
	var draft := _draft()
	if not draft["error"].is_empty():
		_status.text = draft["error"]
		return
	var name := _selected_name() if update else _name.text
	_report(_store.put(name, draft["loadout"], update), "Loadout saved.")
	_refresh_names()


func _select_loadout(index: int) -> void:
	var name := _names.get_item_text(index)
	_name.text = name
	var result := DevCatalog.reconcile(_store.entries[name])
	if not result["error"].is_empty():
		_status.text = result["error"]
		return
	_set_fields(result["loadout"])
	_full_draft = true
	_status.text = "Staged. Apply to use." if result["warnings"].is_empty() else "; ".join(result["warnings"])


func _selected_name() -> String:
	var selected := _names.get_selected_items()
	return "" if selected.is_empty() else _names.get_item_text(selected[0])


func _refresh_names() -> void:
	_names.clear()
	var names: Array = _store.entries.keys()
	names.sort()
	for name in names:
		_names.add_item(name)


func _report(error: String, success := "") -> void:
	_status.text = error if not error.is_empty() else success


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
