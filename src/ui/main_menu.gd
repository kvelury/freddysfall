class_name MainMenu
extends CanvasLayer

## The first screen: the title and Start Game (or Continue and New Game), and
## the Controls page. `?room=` and `?dev=1` launches skip it and boot straight
## into the world, exactly as before the menu existed.

const WORLD := "res://src/world/world.tscn"

## Whether the first menu of this run has been through the boot routing.
static var _booted := false

var _root: Control
var _pages: Array[Control] = []
var _main_page: Control
var _main_list: MenuList
var _confirm_page: Control
var _confirm_list: MenuList
var _controls_page: Control
var _controls_list: MenuList


func _ready() -> void:
	layer = 0
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	if not _booted:
		_booted = true
		if not LaunchArgs.value("room").is_empty() or LaunchArgs.value("dev") == "1":
			# Test launches go straight in, exactly as before the menu existed.
			Scenes.swap.call_deferred(self, load(WORLD).instantiate())
			return
		DevSession.configure(false, false)
		if not LaunchArgs.value("new-game").is_empty():
			Save.erase()
			GameState.reset()
	_build()


func _build() -> void:
	_root = Control.new()
	_root.size = Vector2(320, 180)
	_root.theme = UiTheme.build()
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(320, 180)
	_root.add_child(black)

	_main_page = _page(36, 24)
	_main_page.add_child(UiTheme.title_label("Freddy's Fall", 24))
	_main_list = _list(_main_page)
	if Save.has_game():
		_main_list.add_item("Continue", func() -> void: _start(false))
		_main_list.add_item("New Game", func() -> void: _show(_confirm_page))
	else:
		_main_list.add_item("Start Game", func() -> void: _start(false))
	_main_list.add_item("Controls", func() -> void: _show(_controls_page))

	_confirm_page = _page(76, 8)
	_confirm_page.add_child(_text("Erase your saved game and start over?"))
	_confirm_list = _list(_confirm_page)
	_confirm_list.add_item("No", func() -> void: _show(_main_page))
	_confirm_list.add_item("Yes", func() -> void: _start(true))

	_controls_page = _page(14, 8)
	_controls_page.add_child(_text("Controls"))
	var view := ControlsView.new()
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.show_rows(Controls.visible_rows(null))
	_controls_page.add_child(view)
	_controls_list = _list(_controls_page)
	_controls_list.add_item("Back", func() -> void: _show(_main_page))

	var footer := _text("Arrows / W S choose · Enter select")
	footer.position = Vector2(0, 166)
	_root.add_child(footer)
	_show(_main_page)


## Starts the game: from the save, or from the beginning when `fresh` (which
## erases the save).
func _start(fresh: bool) -> void:
	if fresh:
		Save.erase()
	GameState.reset()
	var world: Node = load(WORLD).instantiate()
	world.from_menu = true
	world.new_game = fresh
	Scenes.swap.call_deferred(self, world)


func _show(page: Control) -> void:
	for each in _pages:
		each.visible = each == page
	var list: MenuList = page.get_meta("list")
	# A confirmation starts on No, the safe answer.
	list.focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _confirm_page.visible or _controls_page.visible:
		_show(_main_page)
		get_viewport().set_input_as_handled()


func _page(y: float, gap: int) -> Control:
	var page := VBoxContainer.new()
	page.position = Vector2(0, y)
	page.custom_minimum_size.x = 320
	page.add_theme_constant_override("separation", gap)
	page.visible = false
	_root.add_child(page)
	_pages.append(page)
	return page


## Adds a MenuList to `page` and remembers it as the one to focus.
func _list(page: Control) -> MenuList:
	var list := MenuList.new()
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(list)
	page.set_meta("list", list)
	return list


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 320
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	return label
