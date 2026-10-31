class_name Toast
extends CanvasLayer

## A line of text near the top of the screen that stays a couple of seconds, and
## a larger one in the middle (`show_centred`) that fades in and out.

const HOLD := 2.5
## The centred line: fades in, holds and fades out.
const BIG_IN := 0.2
const BIG_HOLD := 1.2
const BIG_OUT := 0.4

var _label: Label
var _tween: Tween
var _big: Label
var _big_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_label = Label.new()
	_label.position = Vector2(0, 14)
	_label.custom_minimum_size = Vector2(320, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.visible = false
	add_child(_label)
	_big = Label.new()
	_big.position = Vector2(0, 60)
	_big.custom_minimum_size = Vector2(320, 0)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 16)
	_big.add_theme_color_override("font_color", Color.WHITE)
	_big.visible = false
	add_child(_big)


func show_text(text: String) -> void:
	_label.text = text
	_label.visible = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(HOLD)
	_tween.tween_callback(func() -> void: _label.visible = false)


## A line in the middle of the screen, larger than the rest. It never takes input.
func show_centred(text: String) -> void:
	_big.text = text
	_big.modulate.a = 0.0
	_big.visible = true
	if _big_tween != null:
		_big_tween.kill()
	_big_tween = create_tween()
	_big_tween.tween_property(_big, "modulate:a", 1.0, BIG_IN)
	_big_tween.tween_interval(BIG_HOLD)
	_big_tween.tween_property(_big, "modulate:a", 0.0, BIG_OUT)
	_big_tween.tween_callback(func() -> void: _big.visible = false)
