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


## Drawn in the tool's space, which is world space. White, like the floor, with
## a dashed line through it so a platform that will break does not read as
## floor that will not.
func draw(canvas: CanvasItem) -> void:
	if blinked_off():
		return
	var area := rect
	canvas.draw_rect(area, Color.WHITE)
	var y := area.position.y + area.size.y * 0.5 - 0.5
	var x := area.position.x + 2.0
	while x + 2.0 <= area.end.x - 2.0:
		canvas.draw_rect(Rect2(x, y, 2.0, 1.0), Color.BLACK)
		x += 4.0
