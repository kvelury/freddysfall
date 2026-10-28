class_name PowerPopup
extends CanvasLayer

## Shown when the player gets a power: its name and a diagram of the keys that
## use it. The game is paused until the player dismisses it.

## Input in the first moments is ignored, so a key that was held does not
## close it before it is read.
const MIN_SHOW := 0.4
const OWNER := "power"

var opened := false
var _world: Node
var _name: Label
var _view: ControlsView
var _opened_at := 0
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 26
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_world = get_parent()
	var root := Control.new()
	root.size = Vector2(320, 180)
	root.theme = UiTheme.build()
	add_child(root)
	var centre := CenterContainer.new()
	centre.size = Vector2(320, 180)
	root.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 220
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	column.add_child(_text("NEW POWER", 8))
	_name = _text("", 16)
	column.add_child(_name)
	_view = ControlsView.new()
	_view.centered = true
	_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_view)
	column.add_child(_text("Enter / click to continue", 8))
	hide()


## Shows the popup for upgrade `id`. False, and nothing shown, if another
## modal (the map, a menu) holds the game.
func open(id: String) -> bool:
	if opened or not _world.acquire_modal(OWNER):
		return false
	var def := Upgrades.get_def(id)
	_name.text = String(def.get("name", id))
	var rows: Array = []
	for row_id in def.get("controls", []):
		rows.append(Controls.get_row(String(row_id)))
	_view.show_rows(rows)
	_opened_at = Time.get_ticks_msec()
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened = true
	show()
	return true


func dismiss() -> void:
	if not opened:
		return
	opened = false
	hide()
	Input.mouse_mode = _mouse_before
	_world.release_modal(OWNER)


func _process(_delta: float) -> void:
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not opened or not event.is_pressed() or event.is_echo():
		return
	var wanted := event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") or event.is_action_pressed("jump")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		wanted = true
	if not wanted:
		return
	get_viewport().set_input_as_handled()
	if float(Time.get_ticks_msec() - _opened_at) / 1000.0 >= MIN_SHOW:
		dismiss()


func _text(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label
