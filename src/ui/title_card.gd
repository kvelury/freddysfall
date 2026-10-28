class_name TitleCard
extends CanvasLayer

## Big text across the top of the screen that fades in, holds and fades out:
## the game's title, and later the name of a significant new area. It never
## blocks input. It is under the map, the toast and the menus, and it is not
## "always" processing, so a pause freezes it.

const FADE_IN := 0.3
const FADE_OUT := 0.5

var label: Label
var _tween: Tween


func _ready() -> void:
	layer = 5
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	label = UiTheme.title_label("", 24)
	label.position = Vector2(0, 36)
	label.modulate.a = 0.0
	label.visible = false
	add_child(label)


## How long a card shows in all, for a `hold` in seconds.
static func total(hold: float) -> float:
	return FADE_IN + hold + FADE_OUT


func show_title(text: String, hold: float) -> void:
	if _tween != null:
		_tween.kill()
	label.text = text.to_upper()
	label.modulate.a = 0.0
	label.visible = true
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(label, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(hold)
	_tween.tween_property(label, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func() -> void: label.visible = false)
