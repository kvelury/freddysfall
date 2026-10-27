class_name Shot
extends RefCounted

## One shot in flight: a point that moves in a straight line, one way along a
## row, until the gun finds it has hit something. Plain data, so the gun can
## draw and move every shot itself.

## The drawn size, in pixels (the line is `LENGTH` long along the way it flies).
const LENGTH := 3.0
const THICKNESS := 1.0

var position := Vector2.ZERO
## 1 right, -1 left.
var direction := 1
## Pixels a second.
var speed := 0.0


func _init(start := Vector2.ZERO, way := 1, pixels_per_second := 0.0) -> void:
	position = start
	direction = way
	speed = pixels_per_second


## The box the shot occupies, in world pixels.
func rect() -> Rect2:
	return Rect2(position - Vector2(LENGTH, THICKNESS) * 0.5, Vector2(LENGTH, THICKNESS))
