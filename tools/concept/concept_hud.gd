class_name ConceptHud
extends CanvasLayer

## CONCEPT ONLY. Holds what the overlay should show (captions, title cards,
## the keys or pad buttons being pressed) and logs it per drawn frame, so
## tools/concept/compose.py can draw it crisply at full resolution. In game it
## only blacks out the view behind a title card.

var keys := {}
var stick := Vector2.ZERO
var pad := false
var show_keys := true
var slow := false
var card := false
var card_big := ""
var card_small := ""
## [frame, state] each time the state changes.
var log: Array = []
var _title := ""
var _sub := ""
var _flash := {}
var _last := ""
var _canvas: Node2D


func _ready() -> void:
	layer = 25
	_canvas = Node2D.new()
	_canvas.draw.connect(func() -> void:
		if card:
			_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(Display.VIEWPORT)), Color.BLACK)
	)
	add_child(_canvas)
	reset_keys()


func _process(_delta: float) -> void:
	for k in _flash.keys():
		_flash[k] -= 1
		if _flash[k] <= 0:
			_flash.erase(k)
	_canvas.queue_redraw()
	var pressed: Array = []
	var pulse: Array = []
	for k in keys:
		if bool(keys[k]) or _flash.has(k):
			pressed.append(k)
		if bool(keys[k]) and _flash.has(k):
			pulse.append(k)
	var state := {
		"title": _title, "sub": _sub, "card": card, "big": card_big, "small": card_small,
		"keys": pressed, "pulse": pulse, "stick": [snappedf(stick.x, 0.01), snappedf(stick.y, 0.01)],
		"pad": pad, "show_keys": show_keys, "slow": slow,
	}
	var text := JSON.stringify(state)
	if text != _last:
		_last = text
		log.append([Engine.get_frames_drawn(), state])


func set_caption(title: String, sub: String) -> void:
	_title = title
	_sub = sub


func reset_keys() -> void:
	for k in ["W", "A", "S", "D", "J", "K", "Space", "Shift"]:
		keys[k] = false
	stick = Vector2.ZERO
	_flash.clear()


## Shows `key` pressed for `frames` rendered frames (0 = a short pulse).
func flash(key: String, frames: int) -> void:
	_flash[key] = frames if frames > 0 else 10
