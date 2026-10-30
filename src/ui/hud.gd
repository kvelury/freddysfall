class_name Hud
extends CanvasLayer

## The health and token bar, fixed in the top-left corner. A heart of three
## slots fills with a diamond for each token carried; a bar of pips grows one
## square for each health pip collected, and a pip shows filled while it is
## held. Outlines are red, the HUD's one colour outside black and white.
##
## The HUD shows GameState, less what is still flying in: a pickup taken in a
## room flies to its slot and only counts when it lands. Every change animates
## in whole UI units, by switching pixels and never by fading.

enum Style { WHITE_PLATE, BLACK_PLATE }

const RED := Color("d22b2b")
## Where the heart's top-left sits, in 320 x 180 UI units.
const ORIGIN := Vector2(6, 6)
## The plate reaches this far past the heart and bar.
const MARGIN := 2.0
## Token slot centres in the heart, in the order they fill: left lobe, right
## lobe, point.
const SLOTS: Array[Vector2] = [Vector2(4, 4), Vector2(12, 4), Vector2(8, 8)]
## The bar starts at the heart's right tip. A pip is a 7 x 7 square; neighbours
## share their 1-unit red border, so each pip adds PITCH.
const BAR := Vector2(16, 0)
const PITCH := 8.0
const BAR_HEIGHT := 9.0
## Pips per row before the bar wraps under itself. There is no pip cap, so the
## bar never runs off the screen.
const WRAP := 30
const FLY_TIME := 0.35
const GROW_TIME := 0.15
const POP_TIME := 0.08
const BLINK_TIME := 0.36
const BLINK_STEP := 0.06
const SWEEP_STEP := 0.05
const BUMP_TIME := 0.1
## A flying pickup is drawn again at these offsets in red, for its edge.
const EDGE := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]

## The look, until one is chosen. A dev switch flips it to compare.
static var style := Style.WHITE_PLATE

## What the HUD shows now. They catch up with GameState through the animations.
var shown_tokens := 0
var shown_max := 0
var shown_health := 0
## Pickups on their way: {"kind": &"token" or &"pip", "from", "to", "age"}.
var flights: Array[Dictionary] = []
## How far the newest pip has grown, 0 to 1, while one is growing.
var _grow := -1.0
## Slot effects by key ("t0", "p3"): {"kind": &"pop" or &"blink", "left": seconds}.
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


func slot_centre(index: int) -> Vector2:
	return ORIGIN + SLOTS[clampi(index, 0, SLOTS.size() - 1)]


## The rect of pip `index`'s inside, in UI units.
func pip_rect(index: int) -> Rect2:
	var at := ORIGIN + BAR + Vector2(PITCH * float(index % WRAP), PITCH * float(floori(float(index) / WRAP)))
	return Rect2(at + Vector2.ONE, Vector2(PITCH - 1.0, BAR_HEIGHT - 2.0))


func pip_centre(index: int) -> Vector2:
	return pip_rect(maxi(0, index)).get_center().floor()


## Everything the HUD covers, plate included, for a bar `pips` long.
func plate_rect(pips: int) -> Rect2:
	var box := Rect2(ORIGIN, Vector2(17, 13))
	if pips > 0:
		var columns := mini(pips, WRAP)
		var rows := floori(float(pips - 1) / WRAP) + 1
		box = box.merge(Rect2(ORIGIN + BAR, Vector2(PITCH * columns + 1.0, PITCH * rows + 1.0)))
	return box.grow(MARGIN)


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


func _colours() -> Dictionary:
	if style == Style.BLACK_PLATE:
		return {"plate": Color.BLACK, "full": Color.WHITE, "empty": Color.BLACK}
	return {"plate": Color.WHITE, "full": Color.BLACK, "empty": Color.WHITE}


## Whether slot effect `key` shows the slot filled this frame, given `held`.
func _filled(key: String, held: bool) -> bool:
	if not _effects.has(key) or _effects[key]["kind"] != &"blink":
		return held
	# An emptied slot flashes its old fill on and off before it goes.
	return int(floorf(_effects[key]["left"] / BLINK_STEP)) % 2 == 1


func _fill_colour(key: String, held: bool, colours: Dictionary) -> Color:
	if _effects.has(key) and _effects[key]["kind"] == &"pop":
		return RED
	return colours["full"] if _filled(key, held) else colours["empty"]


func _draw_hud() -> void:
	var colours := _colours()
	var pips := shown_max + (1 if _grow >= 0.0 else 0)
	_canvas.draw_rect(plate_rect(pips), colours["plate"])
	var heart := ORIGIN + (Vector2(0, -1) if _bump > 0.0 else Vector2.ZERO)
	PixelArt.draw(_canvas, "hud_heart", heart, RED)
	for i in SLOTS.size():
		PixelArt.draw(_canvas, "hud_slot", heart + SLOTS[i], _fill_colour("t%d" % i, i < shown_tokens, colours))
	for i in shown_max:
		_draw_pip(i, 1.0, colours)
	if _grow >= 0.0:
		_draw_pip(shown_max, _grow, colours)
	for flight in flights:
		_draw_flight(flight)


## Pip `index`, grown `amount` (0 to 1) along the bar from its left edge.
func _draw_pip(index: int, amount: float, colours: Dictionary) -> void:
	var inside := pip_rect(index)
	var width := roundf(PITCH * clampf(amount, 0.0, 1.0))
	_canvas.draw_rect(Rect2(inside.position - Vector2.ONE, Vector2(width + 1.0, BAR_HEIGHT)), RED)
	if width > 1.0:
		var key := "p%d" % index
		var fill: Color = _fill_colour(key, index < shown_health, colours) if amount >= 1.0 else colours["empty"]
		_canvas.draw_rect(Rect2(inside.position, Vector2(width - 1.0, inside.size.y)), fill)


## A pickup on its way in: white, as it was in the room, with a red edge so it
## reads over black space, white walls and the plate. It speeds up as it goes.
func _draw_flight(flight: Dictionary) -> void:
	var t := clampf(flight["age"] / FLY_TIME, 0.0, 1.0)
	var at: Vector2 = (flight["from"] as Vector2).lerp(flight["to"], t * t).round()
	for colour: Color in [RED, Color.WHITE]:
		var offsets := EDGE if colour == RED else [Vector2.ZERO]
		for offset: Vector2 in offsets:
			if flight["kind"] == &"token":
				PixelArt.draw(_canvas, "token", at + offset, colour)
			else:
				# The pip's plus sign, as HealthPip draws it.
				_canvas.draw_rect(Rect2(at + offset + Vector2(-1, -4), Vector2(2, 8)), colour)
				_canvas.draw_rect(Rect2(at + offset + Vector2(-4, -1), Vector2(8, 2)), colour)
