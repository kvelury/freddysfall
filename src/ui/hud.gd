class_name Hud
extends CanvasLayer

## The hearts and token HUD, fixed in the top-left corner, from the user's
## drawing. A red hexagon frame holds one heart for each hit point: a full heart
## is solid red and an empty one is a red outline with black inside. A column of
## diamonds runs down the left, the top one over the frame's left point, and a
## diamond is drawn only for a token carried: solid gold with no outline, filling
## top first. Nothing is drawn for a token not held, and the frame never moves.
##
## The HUD shows GameState, less what is still flying in: a pickup taken in a
## room flies to its slot and only counts when it lands. Every change animates
## in whole UI units, by switching pixels and never by fading.

const RED := Palette.RED
## Tokens are gold everywhere: in a room, flying, in a 3TM and here.
const GOLD := Palette.GOLD
## An empty heart is black inside its red outline. There is no plate.
const EMPTY := Color.BLACK
## Where the HUD's top-left sits, in 320 x 180 UI units: clear of a room's
## one-cell outer wall, since nothing is drawn behind the HUD.
const ORIGIN := Vector2(14, 14)
## The token column's centre line, and the first diamond's centre, which is also
## the frame's left point. Diamonds are 9 units tall and step down by DIAMOND_STEP,
## so they touch tip to tip.
const COLUMN := Vector2(4, 5)
const DIAMOND_STEP := 8.0
## The frame is a hexagon FRAME_HEIGHT tall with 45 degree end points.
const FRAME_HEIGHT := 11
const POINT := 5
## Hearts start this far right of the left point, and are 7 x 6, PITCH apart.
const HEART_GAP := 6
const HEART_SIZE := Vector2(7, 6)
const PITCH := 9.0
## Hearts per row before the frame wraps: each further row is its own frame
## under the first. There is no heart cap, so the frame never runs off the screen.
const WRAP := 30
const ROW_STEP := 12.0
const FLY_TIME := 0.35
const GROW_TIME := 0.15
const POP_TIME := 0.08
const BLINK_TIME := 0.36
const BLINK_STEP := 0.06
const SWEEP_STEP := 0.05
const BUMP_TIME := 0.1

## What the HUD shows now. They catch up with GameState through the animations.
var shown_tokens := 0
var shown_max := 1
var shown_health := 0
## Pickups on their way: {"kind": &"token" or &"pip", "from", "to", "age"}.
var flights: Array[Dictionary] = []
## How far the frame has grown for the newest heart, 0 to 1, while one grows.
var _grow := -1.0
## Effects by key ("t0" a token, "p3" a heart): {"kind": &"pop" or &"blink", "left": seconds}.
var _effects := {}
var _sweep := 0.0
var _bump := 0.0
var _canvas: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9
	# The UI is laid out in 320 x 180 units and drawn at the screen's finer resolution.
	scale = Vector2.ONE * Display.RENDER_SCALE
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	sync()


## Shows GameState as it is, with nothing flying and nothing animating.
func sync() -> void:
	flights.clear()
	_effects.clear()
	_grow = -1.0
	_sweep = 0.0
	_bump = 0.0
	shown_tokens = GameState.tokens
	shown_max = GameState.max_health
	shown_health = mini(GameState.health, shown_max)
	_redraw()


## A pickup just taken at `world_position` flies into the HUD. Call it after
## GameState has counted it: the HUD holds the count back until it lands.
func fly_in(kind: StringName, world_position: Vector2) -> void:
	var to := slot_centre(GameState.tokens - 1) if kind == &"token" else pip_centre(GameState.max_health - 1)
	flights.append({"kind": kind, "from": to_ui(world_position), "to": to, "age": 0.0})
	_redraw()


## A point in the world as UI units on this layer.
func to_ui(world_position: Vector2) -> Vector2:
	return (get_viewport().canvas_transform * world_position) / float(Display.RENDER_SCALE)


## Diamond `index`'s centre, in UI units.
func slot_centre(index: int) -> Vector2:
	return ORIGIN + COLUMN + Vector2(0, DIAMOND_STEP * float(clampi(index, 0, GameState.TOKEN_CAP - 1)))


## The rect of heart `index`, in UI units.
func pip_rect(index: int) -> Rect2:
	var row := floori(float(index) / WRAP)
	var at := ORIGIN + COLUMN + Vector2(HEART_GAP + PITCH * float(index % WRAP), ROW_STEP * row - 3.0)
	return Rect2(at, HEART_SIZE)


func pip_centre(index: int) -> Vector2:
	return pip_rect(maxi(0, index)).get_center().floor()


## Everything the HUD covers, for a frame of `pips` hearts. The diamonds' column
## counts even when no token is held, so the area never changes size.
func bounds(pips: int) -> Rect2:
	var hearts := maxi(pips, 1)
	var columns := mini(hearts, WRAP)
	var rows := floori(float(hearts - 1) / WRAP) + 1
	var box := Rect2(ORIGIN, Vector2(9, DIAMOND_STEP * (GameState.TOKEN_CAP - 1) + 10.0))
	var frame := Rect2(ORIGIN + Vector2(COLUMN.x, 0), Vector2(PITCH * columns + HEART_GAP + POINT + 1.0, ROW_STEP * (rows - 1) + FRAME_HEIGHT))
	return box.merge(frame)


func busy() -> bool:
	return not flights.is_empty() or not _effects.is_empty() or _grow >= 0.0 or _bump > 0.0 \
			or shown_tokens != _target_tokens() or shown_max != _target_max() or shown_health != _target_health()


func _incoming(kind: StringName) -> int:
	var count := 0
	for flight in flights:
		if flight["kind"] == kind:
			count += 1
	return count


func _target_tokens() -> int:
	return clampi(GameState.tokens - _incoming(&"token"), 0, GameState.TOKEN_CAP)


func _target_max() -> int:
	return maxi(0, GameState.max_health - _incoming(&"pip"))


func _target_health() -> int:
	return clampi(GameState.health - _incoming(&"pip"), 0, _target_max())


func _process(delta: float) -> void:
	if not busy():
		return
	for flight in flights.duplicate():
		flight["age"] += delta
		if flight["age"] >= FLY_TIME:
			flights.erase(flight)
	_step_tokens()
	_step_bar(delta)
	for key in _effects.keys():
		_effects[key]["left"] -= delta
		if _effects[key]["left"] <= 0.0:
			_effects.erase(key)
	_bump = maxf(0.0, _bump - delta)
	_redraw()


func _step_tokens() -> void:
	var target := _target_tokens()
	while shown_tokens < target:
		_effects["t%d" % shown_tokens] = {"kind": &"pop", "left": POP_TIME}
		_bump = BUMP_TIME
		shown_tokens += 1
	while shown_tokens > target:
		shown_tokens -= 1
		_effects["t%d" % shown_tokens] = {"kind": &"blink", "left": BLINK_TIME}


func _step_bar(delta: float) -> void:
	var target_max := _target_max()
	if target_max < shown_max:
		shown_max = target_max
		_grow = -1.0
	if _grow >= 0.0:
		_grow += delta / GROW_TIME
		if _grow >= 1.0:
			_grow = -1.0
			shown_max += 1
	elif shown_max < target_max:
		_grow = 0.0
	var target := mini(_target_health(), shown_max)
	if shown_health > target:
		while shown_health > target:
			shown_health -= 1
			_effects["p%d" % shown_health] = {"kind": &"blink", "left": BLINK_TIME}
		_sweep = 0.0
	elif shown_health < target:
		# Pips fill one at a time, left to right.
		_sweep -= delta
		if _sweep <= 0.0:
			_effects["p%d" % shown_health] = {"kind": &"pop", "left": POP_TIME}
			shown_health += 1
			_sweep = SWEEP_STEP


func _redraw() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## What a slot is filled with: gold for a token, red for a pip. A pop flashes
## white first, for both.
func _full(key: String) -> Color:
	return GOLD if key.begins_with("t") else RED


func _flash(_key: String) -> Color:
	return Color.WHITE


## Whether slot effect `key` shows the slot filled this frame, given `held`.
func _filled(key: String, held: bool) -> bool:
	if not _effects.has(key) or _effects[key]["kind"] != &"blink":
		return held
	# An emptied slot flashes its old fill on and off before it goes.
	return int(floorf(_effects[key]["left"] / BLINK_STEP)) % 2 == 1


func _fill_colour(key: String, held: bool) -> Color:
	if _effects.has(key) and _effects[key]["kind"] == &"pop":
		return _flash(key)
	return _full(key) if _filled(key, held) else EMPTY


func _draw_hud() -> void:
	# The frame, one hexagon for each row of hearts, longer while a heart grows.
	var units := roundi(PITCH * float(shown_max)) + (roundi(PITCH * _grow) if _grow >= 0.0 else 0)
	units = maxi(units, roundi(PITCH))
	var row := 0
	while units > 0:
		_draw_frame(row, mini(units, roundi(PITCH) * WRAP))
		units -= roundi(PITCH) * WRAP
		row += 1
	for i in shown_max:
		_draw_heart(i)
	# Diamonds last, over the frame's left point. A spent token blinks its whole
	# diamond and is gone; there is no empty one.
	var bump := Vector2(0, -1) if _bump > 0.0 else Vector2.ZERO
	for i in GameState.TOKEN_CAP:
		var key := "t%d" % i
		var held := i < shown_tokens
		var blinking: bool = _effects.has(key) and _effects[key]["kind"] == &"blink"
		if not held and not (blinking and _filled(key, false)):
			continue
		var at := slot_centre(i) + bump
		PixelArt.draw(_canvas, "hud_token", at, _fill_colour(key, true) if held else GOLD)
	for flight in flights:
		_draw_flight(flight)


## One hexagon row, `length` units of hearts long: the left point sits under the
## first diamond's centre, 45 degree edges rise to the top and bottom lines,
## and the right end mirrors the left.
func _draw_frame(row: int, length: int) -> void:
	var left := ORIGIN + COLUMN + Vector2(0, ROW_STEP * row)
	var top := left.y - float(POINT)
	var edge := left.x + HEART_GAP - 1.0
	var end := left.x + HEART_GAP - 2.0 + float(length)
	for k in POINT + 1:
		for dir in [-1.0, 1.0]:
			_canvas.draw_rect(Rect2(Vector2(left.x + k, left.y + dir * k), Vector2.ONE), RED)
			_canvas.draw_rect(Rect2(Vector2(end + POINT - k, left.y + dir * k), Vector2.ONE), RED)
	_canvas.draw_rect(Rect2(Vector2(edge, top), Vector2(end - edge + 1.0, 1.0)), RED)
	_canvas.draw_rect(Rect2(Vector2(edge, top + FRAME_HEIGHT - 1.0), Vector2(end - edge + 1.0, 1.0)), RED)


## Heart `index`: solid red when full, a red outline when empty.
func _draw_heart(index: int) -> void:
	var colour := _fill_colour("p%d" % index, index < shown_health)
	var at := pip_rect(index).position
	if colour == EMPTY:
		PixelArt.draw(_canvas, "hud_heart_empty", at, RED)
	else:
		PixelArt.draw(_canvas, "hud_heart", at, colour)


## A pickup on its way in: gold for a token, red for a pip, with no edge. It
## speeds up as it goes.
func _draw_flight(flight: Dictionary) -> void:
	var t := clampf(flight["age"] / FLY_TIME, 0.0, 1.0)
	var at: Vector2 = (flight["from"] as Vector2).lerp(flight["to"], t * t).round()
	if flight["kind"] == &"token":
		# Drawn with PixelArt directly: Token and HealthPip read this file's colours.
		PixelArt.draw(_canvas, "token", at, GOLD)
	else:
		PixelArt.draw(_canvas, "hud_heart", at + Vector2(-3, -3), RED)
