class_name ImprintPlatform
extends RefCounted

## One placed platform: where it is, how long it has left, and how it looks.

## The last stretch of its life, in seconds, when it blinks.
const BLINK_TIME := 1.0
const BLINK_PERIOD := 0.1

## In world pixels.
var rect := Rect2()
var lifetime := 4.0
var age := 0.0


func _init(world_rect: Rect2, seconds: float) -> void:
	rect = world_rect
	lifetime = seconds


func expired() -> bool:
	return age >= lifetime


## Off for every other tenth of a second in the last second.
func blinked_off() -> bool:
	return age > lifetime - BLINK_TIME and int(age / BLINK_PERIOD) % 2 == 1


## How many of the dashes are still showing. They are the platform's clock:
## one goes in each equal share of its life, the leftmost first.
func lines_left() -> int:
	var total := _line_xs().size()
	var left := ceili(float(total) * (lifetime - age) / lifetime)
	return clampi(left, 0, total)


## The dashes still showing, in world pixels. They are the rightmost ones.
func line_rects() -> Array[Rect2]:
	var xs := _line_xs()
	var y := rect.position.y + rect.size.y * 0.5 - 0.5
	var out: Array[Rect2] = []
	for i in range(xs.size() - lines_left(), xs.size()):
		out.append(Rect2(xs[i], y, 2.0, 1.0))
	return out


## Drawn in the tool's space, which is world space. White, like the floor, with
## a dashed line through it so a platform that will break does not read as
## floor that will not.
func draw(canvas: CanvasItem) -> void:
	if blinked_off():
		return
	canvas.draw_rect(rect, Color.WHITE)
	for line in line_rects():
		canvas.draw_rect(line, Color.BLACK)


## Where every dash starts, left to right, when the platform is new.
func _line_xs() -> Array[float]:
	var out: Array[float] = []
	var x := rect.position.x + 2.0
	while x + 2.0 <= rect.end.x - 2.0:
		out.append(x)
		x += 4.0
	return out
