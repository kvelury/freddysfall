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
var _prompt: Label
var _view: ControlsView
## Seconds it has been open, counted in frames (it runs while the game is
## paused, and slow motion does not stretch it).
var _open_for := 0.0


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
	_prompt = _text(Controls.press_any(), 8)
	column.add_child(_prompt)
	hide()


## Shows the popup for upgrade `id`. False, and nothing shown, if another
## modal (the map, a menu) holds the game.
func open(id: String) -> bool:
	if opened or not _world.acquire_modal(OWNER):
		return false
	var def := Upgrades.get_def(id)
	_name.text = def.title
	_prompt.text = Controls.press_any()
	var rows: Array = []
	for row_id in def.controls:
		rows.append(Controls.get_row(String(row_id)))
	_view.show_rows(rows)
	_open_for = 0.0
	opened = true
	show()
	return true


func dismiss() -> void:
	if not opened:
		return
	opened = false
	hide()
	_world.release_modal(OWNER)


func _process(delta: float) -> void:
	if opened:
		_open_for += delta / maxf(Engine.time_scale, 0.001)


func _input(event: InputEvent) -> void:
	if not opened or not Controls.dismisses(event):
		return
	get_viewport().set_input_as_handled()
	if _open_for >= MIN_SHOW:
		dismiss()


func _text(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label
