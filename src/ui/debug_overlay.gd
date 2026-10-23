extends CanvasLayer

var _label: Label
var _errors: Label
var _warp: Label
var _shown := false
var _typing := false
var _typed := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_label = Label.new()
	_label.position = Vector2(12, 14)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.visible = false
	add_child(_label)
	_show_load_errors()
	_warp = Label.new()
	_warp.position = Vector2(12, 160)
	_warp.add_theme_font_size_override("font_size", 8)
	_warp.add_theme_color_override("font_color", Color.WHITE)
	_warp.visible = false
	add_child(_warp)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug"):
		_shown = not _shown
		_label.visible = _shown
	if not _shown:
		return
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_label.text = "FPS %d\nframe %.2f ms\nphysics %.2f ms\n%s" % [int(fps), frame_ms, physics_ms, GameState.abilities.describe()]


## A world that loaded with problems says so on screen in debug builds, so a
## bad room is never mistaken for a working one.
func _show_load_errors() -> void:
	if not OS.is_debug_build() or WorldData.errors.is_empty():
		return
	_errors = Label.new()
	_errors.position = Vector2(12, 40)
	_errors.custom_minimum_size = Vector2(296, 0)
	_errors.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_errors.add_theme_font_size_override("font_size", 8)
	_errors.add_theme_color_override("font_color", Color.WHITE)
	var lines: Array[String] = ["WORLD DATA ERRORS (%d)" % WorldData.errors.size()]
	for i in mini(WorldData.errors.size(), 4):
		lines.append(WorldData.errors[i])
	_errors.text = "\n".join(lines)
	add_child(_errors)


## F4, then a room number and Enter, jumps straight to that room. Debug builds
## only. Escape or F4 again cancels.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F4:
		_set_typing(not _typing)
	elif not _typing:
		return
	elif key.keycode == KEY_ESCAPE:
		_set_typing(false)
	elif key.keycode == KEY_BACKSPACE:
		_typed = _typed.substr(0, _typed.length() - 1)
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		var world := get_parent()
		if world.has_method("warp_to") and not world.warp_to(_typed):
			_typed = ""
			_warp.text = "no such room"
			return
		_set_typing(false)
	elif (key.unicode >= 48 and key.unicode <= 57) or key.unicode == 115 or key.unicode == 83:
		_typed += char(key.unicode).to_lower()
	else:
		return
	_warp.text = "warp to room: %s_" % _typed
	get_viewport().set_input_as_handled()


func _set_typing(on: bool) -> void:
	_typing = on
	_typed = ""
	_warp.visible = on
	_warp.text = "warp to room: _"
