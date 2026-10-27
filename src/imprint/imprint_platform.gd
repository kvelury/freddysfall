class_name ImprintPlatform
extends RefCounted

## One placed platform: where it is, how long it has left, and how it looks. Its
## own width is its clock: one block goes in each equal share of its life, and
## the last block goes with the platform. The order is fixed when it is placed,
## from where the player was: the block farthest from them goes first and the
## one nearest them last (see `removal_order`). A platform that does not shrink
## (`shrinks` false) is the Classic dev mode: full width until it breaks, with a
## dash clock.

## It blinks on and off this often while its last dash, or the next block to go,
## is on show.
const BLINK_PERIOD := 0.1
## The block that goes next blinks for this long before it goes.
const WARN_TIME := 0.25

## In world pixels. `rect` is the footing right now: the whole platform when new,
## then the blocks that still stand. `full_rect` is what was placed.
var rect := Rect2()
var full_rect := Rect2()
var lifetime := 4.0
var age := 0.0
## How many blocks it was placed with, and whether it loses them.
var cells := 1
var shrinks := true
## The block indices (0 = leftmost) in the order they go. The last one lasts the
## whole life.
var order: Array[int] = []


## `player_x` is the player's centre when it was placed, in the same space as
## `world_rect`, and `facing` which way they faced. With no `player_x`, the
## platform's own centre is used.
func _init(world_rect: Rect2, seconds: float, shrinking := true, player_x := NAN, facing := 1) -> void:
	rect = world_rect
	full_rect = world_rect
	lifetime = seconds
	shrinks = shrinking
	cells = maxi(roundi(world_rect.size.x / float(Grid.CELL)), 1)
	var x := player_x if is_finite(player_x) else world_rect.get_center().x
	order = removal_order(cells, world_rect.position.x, x, facing)


## The order the blocks of a platform go in, for a player whose centre was at
## `player_x` when it was placed. Each time, the end of what is left that is
## farther from the player goes, so the platform stays in one piece and the
## block nearest the player is last. When both ends are as far, the one behind
## the player goes (the left one for a player facing right).
static func removal_order(count: int, left_x: float, player_x: float, facing: int) -> Array[int]:
	var out: Array[int] = []
	var cell := float(Grid.CELL)
	var lo := 0
	var hi := count - 1
	while lo < hi:
		var to_lo := absf(left_x + (float(lo) + 0.5) * cell - player_x)
		var to_hi := absf(left_x + (float(hi) + 0.5) * cell - player_x)
		var left_goes := to_lo > to_hi if not is_equal_approx(to_lo, to_hi) else facing > 0
		if left_goes:
			out.append(lo)
			lo += 1
		else:
			out.append(hi)
			hi -= 1
	out.append(lo)
	return out


## The block that lasts the whole life.
func last_cell() -> int:
	return order[order.size() - 1]


func expired() -> bool:
	return age >= lifetime


## How many blocks still stand: one is lost in each equal share of the life.
func blocks_left() -> int:
	if not shrinks:
		return cells
	return clampi(ceili(float(cells) * (lifetime - age) / lifetime), 0, cells)


## The index (0 = leftmost) of the block that goes next, or -1 if none is left.
func next_cell() -> int:
	var left := blocks_left()
	if left <= 0 or not shrinks:
		return -1
	return order[cells - left]


## Seconds until the next block goes.
func time_to_next() -> float:
	var removed := cells - blocks_left()
	return lifetime * float(removed + 1) / float(cells) - age


## How long the next block blinks: WARN_TIME, but never more than half a share,
## so a platform with a very short share is not blinking all the time.
func warn_time() -> float:
	return minf(WARN_TIME, lifetime / float(cells) * 0.5)


## Whether the block that goes next is blinked off at this moment.
func blinking_off() -> bool:
	return shrinks and next_cell() >= 0 and time_to_next() <= warn_time() and int(age / BLINK_PERIOD) % 2 == 1


## The footing for `left` blocks standing, in world pixels: the blocks not yet
## in the order's first `cells - left`, which are always one run.
func footing(left: int) -> Rect2:
	var from := cells
	for i in range(cells - left, cells):
		from = mini(from, order[i])
	var cell := float(Grid.CELL)
	return Rect2(full_rect.position.x + float(from) * cell, full_rect.position.y, float(left) * cell, full_rect.size.y)


## Brings `rect` in line with `age`. Returns the rects of the blocks that just
## went (empty most ticks), so the caller can shatter them. It never returns the
## last block: its removal is the platform's expiry.
func update_footing() -> Array[Rect2]:
	var gone: Array[Rect2] = []
	var left := blocks_left()
	if not shrinks or left <= 0:
		return gone
	var before := rect
	var after := footing(left)
	if after.size.x >= before.size.x - 0.5:
		return gone
	var cell := float(Grid.CELL)
	var x := before.position.x
	while x < after.position.x - 0.5:
		gone.append(Rect2(x, before.position.y, cell, before.size.y))
		x += cell
	x = after.end.x
	while x < before.end.x - 0.5:
		gone.append(Rect2(x, before.position.y, cell, before.size.y))
		x += cell
	rect = after
	return gone


## Classic only. Off for every other tenth of a second once only the last dash
## is left.
func blinked_off() -> bool:
	return age > lifetime - blink_time() and int(age / BLINK_PERIOD) % 2 == 1


## Classic only. How long the blink lasts at the end: the last dash's share of
## the life.
func blink_time() -> float:
	return lifetime / float(maxi(_line_xs().size(), 1))


## Classic only. How many of the dashes are still showing. They are the
## platform's clock: one goes in each equal share of its life, the leftmost
## first.
func lines_left() -> int:
	var total := _line_xs().size()
	var left := ceili(float(total) * (lifetime - age) / lifetime)
	return clampi(left, 0, total)


## Classic only. The dashes still showing, in world pixels. They are the
## rightmost ones.
func line_rects() -> Array[Rect2]:
	var xs := _line_xs()
	var y := rect.position.y + rect.size.y * 0.5 - 0.5
	var out: Array[Rect2] = []
	for i in range(xs.size() - lines_left(), xs.size()):
		out.append(Rect2(xs[i], y, 2.0, 1.0))
	return out


## What is showing right now. The block that blinks off is always an end of the
## footing, so the drawn area stays one rect.
func drawn_rect() -> Rect2:
	var shown := rect
	if blinking_off():
		var cell := float(Grid.CELL)
		if full_rect.position.x + float(next_cell()) * cell < shown.position.x + 0.5:  # the left end goes next
			shown.position.x += cell
		shown.size.x -= cell
	return shown


## Drawn in the tool's space, which is world space. White, like the floor.
## A platform that shrinks has a dotted black border one pixel inside its edge,
## so it reads as one that was placed; a Classic one has a dashed line through
## it instead.
func draw(canvas: CanvasItem) -> void:
	if not shrinks:
		if blinked_off():
			return
		canvas.draw_rect(rect, Color.WHITE)
		for line in line_rects():
			canvas.draw_rect(Display.snap_rect(line), Color.BLACK)
		return
	var shown := drawn_rect()
	if shown.size.x <= 0.0:
		return
	canvas.draw_rect(shown, Color.WHITE)
	var inner := shown.grow(-1.0)
	var x0 := int(inner.position.x)
	var y0 := int(inner.position.y)
	var x1 := int(inner.end.x) - 1
	var y1 := int(inner.end.y) - 1
	var origin := full_rect.position
	for x in range(x0, x1 + 1):
		_dot(canvas, x, y0, origin)
		_dot(canvas, x, y1, origin)
	for y in range(y0 + 1, y1):
		_dot(canvas, x0, y, origin)
		_dot(canvas, x1, y, origin)


## One pixel of the border, on every other pixel. The parity is measured from
## the placed platform's corner so the dots do not shimmer as it shrinks.
func _dot(canvas: CanvasItem, x: int, y: int, origin: Vector2) -> void:
	if (x - int(origin.x) + y - int(origin.y)) % 2 == 0:
		canvas.draw_rect(Rect2(x, y, 1, 1), Color.BLACK)


## Classic only. Where every dash starts, left to right, when the platform is
## new.
func _line_xs() -> Array[float]:
	var out: Array[float] = []
	var x := full_rect.position.x + 2.0
	while x + 2.0 <= full_rect.end.x - 2.0:
		out.append(x)
		x += 4.0
	return out
