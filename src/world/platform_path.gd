class_name PlatformPath
extends Mover

## Where a moving platform is at each physics tick. It waits at the end it is
## drawn at, slides at a set speed to the far end of its track, waits, and
## slides back. It is worked out from whole ticks, so the game and the reach
## solver get the same rect for the same tick.

## How long it waits at each end, in seconds, when the legend does not say.
const DEFAULT_PAUSE := 0.2

## The cells the platform covers where it is drawn.
var start_cells := Rect2i()
## From the drawn end towards the far end: a unit step along x or y.
var direction := Vector2i.RIGHT
## How many cells it travels.
var cells := 0
## Pixels per second while it slides.
var speed := 60.0
var travel_ticks := 1
var pause_ticks := 0


func _init(platform_id: String, drawn: Rect2i, toward: Vector2i, length: int, px_per_second: float, pause_seconds: float) -> void:
	id = platform_id
	start_cells = drawn
	direction = toward
	cells = length
	speed = px_per_second
	travel_ticks = maxi(1, roundi(distance() / speed * float(TICKS_PER_SECOND)))
	pause_ticks = maxi(0, roundi(pause_seconds * float(TICKS_PER_SECOND)))


## How far it travels, in pixels.
func distance() -> float:
	return float(cells * Grid.CELL)


## Ticks for a full trip there and back, with both pauses.
func period() -> int:
	return 2 * (travel_ticks + pause_ticks)


func is_horizontal() -> bool:
	return direction.y == 0


## How far along the track it is at `tick`, from 0 at the drawn end to 1 at
## the far end.
func progress(tick: int) -> float:
	var t := posmod(tick, period())
	if t < pause_ticks:
		return 0.0
	t -= pause_ticks
	if t < travel_ticks:
		return float(t) / float(travel_ticks)
	t -= travel_ticks
	if t < pause_ticks:
		return 1.0
	t -= pause_ticks
	return 1.0 - float(t) / float(travel_ticks)


## Its rect at `tick`, in room pixels.
func rect_at(tick: int, _body := 0) -> Rect2:
	var rect := Grid.cell_rect(start_cells)
	rect.position += Vector2(direction) * distance() * progress(tick)
	return rect


## Every cell it covers on the way, in room cells.
func swept_cells() -> Rect2i:
	var far := Rect2i(start_cells.position + direction * cells, start_cells.size)
	return start_cells.merge(far)


## The row of cells just above everywhere it goes: where a rider stands. It is
## kept clear, so riding never scrapes, crushes or kills the player.
func band_cells() -> Rect2i:
	var swept := swept_cells()
	return Rect2i(swept.position.x, swept.position.y - 1, swept.size.x, 1)


