class_name PauseMenu
extends CanvasLayer

## The pause menu: Resume, Controls, Dev tools (when dev is available) and
## Main menu over a dimmed game. Esc or P
## opens and closes it. It takes the world's modal, so the game is paused
## while it is open, and it waits for an animation (a door slide, a death, a
## save) to finish before it opens, as the dev panel does.

const OWNER := "pause"
const MENU_WIDTH := 140
const CONTROLS_WIDTH := 280

var opened := false
var _world: Node
var _pending := false
var _on_controls := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _panel: PanelContainer
var _heading: Label
var _status: Label
var _list: MenuList
var _view: ControlsView
var _back: MenuList
var _column: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_world = get_parent()
	_build()
	hide()


func _build() -> void:
	var root := Control.new()
	root.size = Vector2(320, 180)
	root.theme = UiTheme.build()
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = Vector2(320, 180)
	root.add_child(shade)
	var centre := CenterContainer.new()
	centre.size = Vector2(320, 180)
	root.add_child(centre)
	_panel = PanelContainer.new()
	centre.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_panel.add_child(margin)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	margin.add_child(_column)
	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_heading)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 1, 1, 0.6)
	_column.add_child(_status)
	_list = MenuList.new()
	_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_list)
	_view = ControlsView.new()
	_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_view)
	_back = MenuList.new()
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.add_item("Back", _show_list)
	_column.add_child(_back)
	_show_list()


## The items are rebuilt each time, since Dev tools is there only when dev is
## available.
func _fill_list() -> void:
	_list.clear()
	_list.add_item("Resume", close)
	_list.add_item("Controls", _show_controls)
	if DevSession.available:
		_list.add_item("Dev tools", _open_dev_tools)
	_list.add_item("Main menu", func() -> void: _world.leave_to_menu())


## Gives the game back and opens the dev panel, which closes to the game.
func _open_dev_tools() -> void:
	close()
	_world.get_node("DevPanel").open_panel()


func _show_list() -> void:
	_on_controls = false
	_heading.text = "Paused"
	_status.text = DevSession.status_line()
	_status.visible = DevSession.isolated()
	_fill_list()
	_column.custom_minimum_size.x = MENU_WIDTH
	_list.show()
	_view.hide()
	_back.hide()
	_list.focus_first()


func _show_controls() -> void:
	_on_controls = true
	_heading.text = "Controls"
	_status.hide()
	_column.custom_minimum_size.x = CONTROLS_WIDTH
	_view.show_rows(Controls.visible_rows(GameState.abilities))
	_list.hide()
	_view.show()
	_back.show()
	_back.focus_first()


## Opens the menu. Does nothing if the map or another panel holds the game.
func open() -> void:
	if opened or not _world.acquire_modal(OWNER):
		return
	opened = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_list()
	show()


## Closes the menu and gives the game back. The world holds the play keys
## until they are let go, so the Space or click that picked Resume is not
## also a shot or a platform.
func close() -> void:
	if not opened:
		return
	opened = false
	_pending = false
	hide()
	Input.mouse_mode = _mouse_before
	get_viewport().gui_release_focus()
	_world.release_modal(OWNER)


func _process(_delta: float) -> void:
	if _pending and not _world.is_busy() and _world.modal_owner.is_empty():
		_pending = false
		open()
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if opened:
		if _on_controls:
			_show_list()
		else:
			close()
	elif _world.is_busy():
		_pending = true
	else:
		open()
