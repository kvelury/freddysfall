class_name Toast
extends CanvasLayer

## A line of text near the top of the screen that stays a couple of seconds.

const HOLD := 2.5

var _label: Label
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	_label = Label.new()
	_label.position = Vector2(0, 14)
	_label.custom_minimum_size = Vector2(320, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.visible = false
	add_child(_label)


func show_text(text: String) -> void:
	_label.text = text
	_label.visible = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(HOLD)
	_tween.tween_callback(func() -> void: _label.visible = false)
