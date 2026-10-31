class_name GameOver
extends CanvasLayer

## The screen after a death that sends the player back to their save room:
## the picture fades to black, "GAME OVER" comes up with a line telling the
## player to continue, and `continued` is emitted when they press what dismisses
## the power popup (Enter, Space, a click, W, Up or Escape). The
## world then builds the save room behind the black and calls `reveal`, which
## fades it away. It is over the HUD and under the dev panel, and it is not
## "always" processing, so an open dev panel freezes it.

signal continued

const FADE_OUT := 0.5
const TEXT_IN := 0.3
## Input in the first moments of the prompt is ignored, so a key that was held
## does not skip it before it is read.
const MIN_SHOW := 0.4
const REVEAL := 0.4

## Between `open` and the key: the screen is up and the pause key is not ours to
## give away. Tests set `scripted` and the screen continues as soon as it is up.
var active := false
var scripted := false

var _black: ColorRect
var _title: Label
var _prompt: Label
var _tween: Tween
var _waiting := false
var _shown_at := 0
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _mouse_held := false


func _ready() -> void:
	layer = 28
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.size = Vector2(320, 180)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_title = UiTheme.title_label("Game over", 24)
	_title.position = Vector2(0, 62)
	add_child(_title)
	_prompt = Label.new()
	_prompt.text = "Enter / click to continue"
	_prompt.position = Vector2(0, 104)
	_prompt.custom_minimum_size = Vector2(320, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.add_theme_color_override("font_color", Color.WHITE)
	add_child(_prompt)
	clear()


## Whether the black is up or fading.
func shown() -> bool:
	return visible


## Fades to black and shows the text. `continued` follows a key.
func open() -> void:
	_stop()
	_hold_mouse()
	active = true
	_waiting = false
	_black.modulate.a = 0.0
	_title.modulate.a = 0.0
	_prompt.modulate.a = 0.0
	show()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(_black, "modulate:a", 1.0, FADE_OUT)
	_tween.tween_property(_title, "modulate:a", 1.0, TEXT_IN)
	_tween.tween_property(_prompt, "modulate:a", 1.0, TEXT_IN)
	_tween.tween_callback(_ready_for_key)


## The text goes at once and the black fades away, once the room behind it is
## built. Does nothing if the screen is not up.
func reveal() -> void:
	if not visible:
		return
	_stop()
	_title.modulate.a = 0.0
	_prompt.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(_black, "modulate:a", 0.0, REVEAL)
	_tween.tween_callback(hide)


## Drops the screen at once.
func clear() -> void:
	_stop()
	_release_mouse()
	active = false
	_waiting = false
	hide()


## The cursor shows while the screen is up, so a click can dismiss it, as it does
## for the power popup.
func _hold_mouse() -> void:
	if _mouse_held:
		return
	_mouse_held = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _release_mouse() -> void:
	if not _mouse_held:
		return
	_mouse_held = false
	Input.mouse_mode = _mouse_before


func _stop() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _ready_for_key() -> void:
	_waiting = true
	_shown_at = Time.get_ticks_msec()
	if scripted:
		_continue()


func _continue() -> void:
	if not _waiting:
		return
	_waiting = false
	active = false
	_release_mouse()
	continued.emit()


func _input(event: InputEvent) -> void:
	if not active or not event.is_pressed() or event.is_echo():
		return
	# The same keys as the power popup. Escape is the pause key, so it is taken
	# here and does not also open the pause menu afterwards.
	var wanted := event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") or event.is_action_pressed("jump")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		wanted = true
	if not wanted:
		return
	get_viewport().set_input_as_handled()
	if _waiting and float(Time.get_ticks_msec() - _shown_at) / 1000.0 >= MIN_SHOW:
		_continue()
