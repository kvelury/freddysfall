class_name SettingsPage
extends VBoxContainer

## The Controls page of Settings, where the player changes what each action is
## bound to, for the keyboard and for a controller. It is used by the main menu
## and the pause menu.
##
## The first row picks the device (Left / Right switches). Each action then has
## two slots: Up / Down choose the action, Left / Right the slot, Enter or A
## starts a capture, and the next key (or button) is the new binding. Escape
## (Start or Back on a controller) cancels a capture. If another action has the
## input, the two swap, so nothing is left unbound (see InputBindings.rebind).
## Changes are saved as they are made. "Reset" puts the device's tab back to
## the defaults. Escape or B, or the Back row, leaves.

signal back_requested

const ROW_HEIGHT := 11
const LABEL_WIDTH := 114

## The rows, top to bottom: the device, an action each, Reset and Back.
var _count := 0
var _selected := 0
var _slot := 0
var _kind_index := 0
var _capturing := false
var _status := ""
var _rows_box: VBoxContainer
var _note: Label
var _bindings: Node
var _actions: Array


func _init() -> void:
	add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = "Controls"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 8)
	add_child(title)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	_rows_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_rows_box)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 8)
	_note.modulate = Color(1, 1, 1, 0.6)
	add_child(_note)


func _ready() -> void:
	_bindings = get_node("/root/InputBindings")
	_actions = _bindings.ACTIONS
	_count = _actions.size() + 3
	visibility_changed.connect(_on_visibility)
	_on_visibility()


## The kind of device being edited.
func kind() -> String:
	return ["keyboard", "controller"][_kind_index]


## Opens on the tab of the device the player is using, on its first row.
func start() -> void:
	_kind_index = 1 if Controls.device == "controller" else 0
	_selected = 0
	_slot = 0
	_capturing = false
	_status = ""
	_refresh()


func _on_visibility() -> void:
	if is_visible_in_tree():
		start()


## The index of the row for `action`, 1 for the first.
func _action_at(row: int) -> String:
	return _actions[row - 1]


func _refresh() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	var device_row := _row(0, "")
	var device_text := "< %s >" % ("Keyboard" if _kind_index == 0 else "Controller")
	device_row.add_child(_label(device_text, 200))
	_rows_box.add_child(device_row)
	for i in _actions.size():
		var action: String = _actions[i]
		var row := _row(i + 1, _bindings.LABELS[action])
		for fixed: Dictionary in _bindings.fixed(action, kind()):
			var cap := KeyCap.new(Controls.binding_text(fixed))
			cap.modulate = Color(1, 1, 1, 0.5)
			row.add_child(cap)
		var list: Array = _bindings.get_bindings(action, kind())
		for slot in _bindings.SLOTS:
			var text: String = Controls.binding_text(list[slot]) if slot < list.size() else "-"
			var picked: bool = _selected == i + 1 and _slot == slot
			if picked and _capturing:
				text = "?"
			var cap := KeyCap.new(text)
			cap.selected = picked
			row.add_child(cap)
		_rows_box.add_child(row)
	var reset := _row(_count - 2, "")
	reset.add_child(_label("Reset to defaults", 200))
	_rows_box.add_child(reset)
	var back := _row(_count - 1, "")
	back.add_child(_label("Back", 200))
	_rows_box.add_child(back)
	_note.text = _note_text()


func _note_text() -> String:
	if _capturing:
		if kind() == "keyboard":
			return "Press a key (Esc cancels)"
		return "Press a button (Start or Back cancels)"
	if not _status.is_empty():
		return _status
	if _selected >= 1 and _selected <= _actions.size():
		return "Left / Right choose a slot, Enter changes it"
	return " "


## A row: the selection mark, then `text` (an action's name). Callers add the
## rest.
func _row(index: int, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	row.add_theme_constant_override("separation", 3)
	var mark := _label(">" if index == _selected else "", 8)
	row.add_child(mark)
	if not text.is_empty():
		row.add_child(_label(text, LABEL_WIDTH))
	return row


func _label(text: String, width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	return label


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _capturing:
		_capture(event)
		return
	if not event.is_pressed() or event is InputEventMouse or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("look_up"):
		_move(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("look_down"):
		_move(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_side(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_side(1)
	elif event.is_action_pressed("ui_accept"):
		_accept()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_selected = posmod(_selected + step, _count)
	_status = ""
	_refresh()


func _side(step: int) -> void:
	_status = ""
	if _selected == 0:
		_kind_index = posmod(_kind_index + step, 2)
	elif _selected <= _actions.size():
		_slot = clampi(_slot + step, 0, _bindings.SLOTS - 1)
	_refresh()


func _accept() -> void:
	_status = ""
	if _selected == 0:
		_kind_index = 1 - _kind_index
	elif _selected <= _actions.size():
		_capturing = true
	elif _selected == _count - 2:
		_bindings.reset(kind())
		_status = "Defaults restored"
	else:
		back_requested.emit()
		return
	_refresh()


## While capturing, every event is taken here so none reaches the game or a
## menu. The first key (or button, or push of a stick) that can be bound is
## the new binding; the cancel input ends the capture.
func _capture(event: InputEvent) -> void:
	if event is InputEventMouse:
		return
	var cancel := false
	if event is InputEventKey and event.pressed and not event.echo:
		cancel = event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE
	elif event is InputEventJoypadButton and event.pressed:
		cancel = event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_BACK
	var binding := Controls.binding_from_event(event)
	if not cancel and (binding.is_empty() or Controls.binding_kind(binding) != kind()):
		# Not a thing the tab binds: a key on the controller tab, a release, a
		# stick not pushed far. It is taken and ignored.
		if event.is_pressed() or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	_capturing = false
	if not cancel:
		var result: Dictionary = _bindings.rebind(_action_at(_selected), _slot, binding)
		_status = String(result["note"])
	_refresh()
