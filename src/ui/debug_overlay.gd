extends CanvasLayer

var _label: Label
var _errors: Label
var _shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_label = Label.new()
	_label.position = Vector2(12, 14)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.visible = false
	add_child(_label)
	_show_load_errors()


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
