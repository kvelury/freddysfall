extends CanvasLayer

var _label: Label
var _shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_label = Label.new()
	_label.position = Vector2(12, 14)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug"):
		_shown = not _shown
		_label.visible = _shown
	if not _shown:
		return
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_label.text = "FPS %d\nframe %.2f ms\nphysics %.2f ms" % [int(fps), frame_ms, physics_ms]
