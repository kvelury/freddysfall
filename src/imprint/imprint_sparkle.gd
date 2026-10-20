class_name ImprintSparkle
extends RefCounted

## The small plus that goes round a platform the player can reach. It is drawn
## by ImprintTool. Where it is, and when it shows, are pure functions of time,
## so the tests ask them directly.

## Pixels a second along the path, and the cycle it is on for, then off for.
const SPEED := 60.0
const ON := 0.2
const OFF := 0.1
## The trail: single pixels this far behind the plus, along the path. They get
## further apart toward the end, so the trail thins out like a falling star's.
## It does not blink.
const TRAIL: Array[float] = [3.0, 5.0, 7.0, 10.0, 13.0, 17.0]


## Whether the sparkle shows at `time`: on for most of each cycle, off for a beat.
static func visible(time: float) -> bool:
	return fposmod(time, ON + OFF) < ON


## The trail behind the sparkle when its centre is `distance` along the path
## round `area`, nearest first.
static func trail(area: Rect2, distance: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for back in TRAIL:
		out.append(point(area, distance - back))
	return out


## The centre of the sparkle `distance` pixels along its path round `area`,
## clockwise from the top left: along the top, down the right side, back along
## the bottom, and up the left. The path is a rectangle that clears the area by
## a pixel, and it wraps. Whole pixels, so the plus never smears.
static func point(area: Rect2, distance: float) -> Vector2:
	var left := area.position.x - 3.0
	var top := area.position.y - 3.0
	var width := area.size.x + 5.0
	var height := area.size.y + 5.0
	var d := fposmod(distance, 2.0 * (width + height))
	var at := Vector2.ZERO
	if d < width:
		at = Vector2(left + d, top)
	elif d < width + height:
		at = Vector2(left + width, top + d - width)
	elif d < 2.0 * width + height:
		at = Vector2(left + width - (d - width - height), top + height)
	else:
		at = Vector2(left, top + height - (d - 2.0 * width - height))
	return at.floor()
