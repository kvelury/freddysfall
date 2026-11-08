class_name Hud
extends CanvasLayer

## The hearts and token HUD, fixed in the top-left corner. A solid blood-red
## rectangle holds one black heart for each hit point: a full heart is a black
## outline with the heart red inside it and an empty one is solid black. A dark
## red shadow sits one unit up and left of the rectangle, so its bottom and right
## edges are clean. Hanging off the rectangle's bottom-left is a small tab of the
## same red with its own shadow, 4 units wider for each token carried, and a small
## gold diamond sits in each of its slots, left to right: solid gold with no
## outline. With no token held there is no tab, and the rectangle never moves.
##
## The HUD shows GameState, less what is still flying in: a pickup taken in a
## room flies to its slot and only counts when it lands. Every change animates
## in whole UI units, by switching pixels and never by fading.

const RED := Palette.RED
## The bar the hearts sit on: a deeper blood red than the heart colour, which
## still shows in flights and a landing heart.
const BAR := Color("8a1414")
## Tokens are gold everywhere: in a room, flying, in a 3TM and here.
const GOLD := Palette.GOLD
## An empty heart is solid black. There is no plate.
const EMPTY := Color.BLACK
## The ink of every heart, on the red bar.
const INK := Color.BLACK
## Where the rectangle's top-left sits, in 320 x 180 UI units: clear of a room's
## one-cell outer wall (the shadow reaches one unit further up and left), since
## nothing is drawn behind the HUD.
const ORIGIN := Vector2(14, 14)
## The shadow behind the rectangle: a dark shade of the bar red, one unit up
## and left, so the rectangle's bottom and right edges stay solid.
const SHADOW := Color("3a0a0a")
const SHADOW_OFFSET := 1.0
## The rectangle is BAR_HEIGHT tall: one unit of bar above and below the hearts,
## and PAD of bar at each end. Hearts are 7 x 6, PITCH apart, so n hearts make a
## rectangle 9n wide.
const PAD := 1.0
const BAR_HEIGHT := 8.0
const HEART_SIZE := Vector2(7, 6)
const PITCH := 9.0
## Token diamonds are 3 x 3, TOKEN_PITCH apart, in a tab flush under the rectangle
## and level with its left edge. The tab is TAB_HEIGHT tall (a unit of bar above
## and below the diamond) and TOKEN_PITCH * n + 1 wide for n tokens, so a unit of
## bar shows at each end and between diamonds. Slots fill left to right.
const TOKEN_SIZE := 3.0
const TOKEN_PITCH := 4.0
const TAB_HEIGHT := 5.0
## Hearts per row before the rectangle wraps: each further row is its own
## rectangle under the token row. There is no heart cap, so it never runs off the
## screen.
const WRAP := 30
## From one rectangle's top to the next: the bar, the token tab under the first
## and a clear unit before the next shadow.
const ROW_STEP := 15.0
const FLY_TIME := 0.35
const GROW_TIME := 0.15
const POP_TIME := 0.08
const BLINK_TIME := 0.36
const BLINK_STEP := 0.06
const SWEEP_STEP := 0.05

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


## Token slot `index`'s centre, in UI units: the middle of its 3 x 3 diamond in the
## tab. Slots fill left to right.
func slot_centre(index: int) -> Vector2:
	var slot := clampi(index, 0, GameState.TOKEN_CAP - 1)
	return Vector2(ORIGIN.x + TOKEN_PITCH * float(slot) + 2.0, ORIGIN.y + BAR_HEIGHT + 2.0)


## The rect of heart `index`, in UI units.
func pip_rect(index: int) -> Rect2:
	var row := floori(float(index) / WRAP)
	var at := ORIGIN + Vector2(PAD + PITCH * float(index % WRAP), PAD + ROW_STEP * row)
	return Rect2(at, HEART_SIZE)


func pip_centre(index: int) -> Vector2:
	return pip_rect(maxi(0, index)).get_center().floor()


## Everything the HUD covers, for a frame of `pips` hearts: the shadow, the
## rectangle and the token tab under the first one. The tab counts at its full
## size even when no token is held, so the area never changes size.
func bounds(pips: int) -> Rect2:
	var hearts := maxi(pips, 1)
	var columns := mini(hearts, WRAP)
	var rows := floori(float(hearts - 1) / WRAP) + 1
	var corner := ORIGIN - Vector2.ONE * SHADOW_OFFSET
	var width := maxf(PITCH * columns, tab_width(GameState.TOKEN_CAP))
	var bottom := maxf(ROW_STEP * (rows - 1) + BAR_HEIGHT, BAR_HEIGHT + TAB_HEIGHT)
	return Rect2(corner, Vector2(width, bottom) + Vector2.ONE * SHADOW_OFFSET)


func busy() -> bool:
	return not flights.is_empty() or not _effects.is_empty() or _grow >= 0.0 \
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
	_redraw()


func _step_tokens() -> void:
	var target := _target_tokens()
	while shown_tokens < target:
		_effects["t%d" % shown_tokens] = {"kind": &"pop", "left": POP_TIME}
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
	# The rectangle, one for each row of hearts, longer while a heart grows. Every
	# shadow goes down before any bar, so the tab's shadow, which reaches up into the
	# rectangle's bottom row, never paints over it.
	var units := roundi(PITCH * float(shown_max)) + (roundi(PITCH * _grow) if _grow >= 0.0 else 0)
	units = maxi(units, roundi(PITCH))
	var frames: Array[Array] = []
	var row := 0
	while units > 0:
		frames.append(frame_rects(row, mini(units, roundi(PITCH) * WRAP)))
		units -= roundi(PITCH) * WRAP
		row += 1
	var tab := tab_rects(tab_slots())
	if not tab.is_empty():
		frames.append(tab)
	for rects in frames:
		_canvas.draw_rect(rects[0], SHADOW)
	for rects in frames:
		_canvas.draw_rect(rects[1], BAR)
	for i in shown_max:
		_draw_heart(i)
	# Diamonds last, in the tab under the rectangle. A spent token blinks its whole
	# diamond and is gone; there is no empty one.
	for i in GameState.TOKEN_CAP:
		var key := "t%d" % i
		var held := i < shown_tokens
		var blinking: bool = _effects.has(key) and _effects[key]["kind"] == &"blink"
		if not held and not (blinking and _filled(key, false)):
			continue
		PixelArt.draw(_canvas, "hud_token", slot_centre(i), _fill_colour(key, true) if held else GOLD)
	for flight in flights:
		_draw_flight(flight)


## One row's rectangle, `length` units of hearts long (9 for each), under its
## shadow: [shadow, bar] as rects.
func frame_rects(row: int, length: int) -> Array[Rect2]:
	var top_left := ORIGIN + Vector2(0, ROW_STEP * row)
	var size := Vector2(float(length), BAR_HEIGHT)
	return [Rect2(top_left - Vector2.ONE * SHADOW_OFFSET, size), Rect2(top_left, size)]


## The tab's width for `slots` token slots: a unit of bar at each end and between.
func tab_width(slots: int) -> float:
	return TOKEN_PITCH * float(slots) + 1.0


## How many slots the tab holds this frame: the tokens shown, and any spent one
## still blinking, so the tab shrinks only once the blink is over.
func tab_slots() -> int:
	var slots := shown_tokens
	for i in range(shown_tokens, GameState.TOKEN_CAP):
		if _effects.has("t%d" % i) and _effects["t%d" % i]["kind"] == &"blink":
			slots = i + 1
	return slots


## The tab under the first rectangle, [shadow, bar] like `frame_rects`: flush under
## the bar, level with its left edge, `slots` wide. Empty when there are none.
func tab_rects(slots: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if slots <= 0:
		return rects
	var top_left := ORIGIN + Vector2(0, BAR_HEIGHT)
	var size := Vector2(tab_width(slots), TAB_HEIGHT)
	rects.append(Rect2(top_left - Vector2.ONE * SHADOW_OFFSET, size))
	rects.append(Rect2(top_left, size))
	return rects


## How heart `index` is drawn: the picture and its colour, from its fill
## colour. A full heart is a black outline over a heart-red fill (see `_draw_heart`), an empty one is solid
## black, and a landing one flashes solid white.
func heart_look(index: int) -> Array:
	var colour := _fill_colour("p%d" % index, index < shown_health)
	if colour == EMPTY:
		return ["hud_heart", INK]
	if colour == RED:
		return ["hud_heart_empty", INK]
	return ["hud_heart", colour]


func _draw_heart(index: int) -> void:
	var look := heart_look(index)
	# A full heart is filled with the heart red under its black outline, so it
	# reads against the darker bar.
	if look[0] == "hud_heart_empty":
		PixelArt.draw(_canvas, "hud_heart", pip_rect(index).position, RED)
	PixelArt.draw(_canvas, look[0], pip_rect(index).position, look[1])


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
