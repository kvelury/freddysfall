class_name Movers
extends RefCounted

## A room's moving platforms as a body sees them: each path, shifted to where
## the room is. The game gives it the room's position, the solver works in
## room pixels and leaves it at zero.

var paths: Array[PlatformPath] = []
var origin := Vector2.ZERO


func _init(list: Array[PlatformPath] = [], at := Vector2.ZERO) -> void:
	paths = list
	origin = at


func size() -> int:
	return paths.size()


func is_empty() -> bool:
	return paths.is_empty()


## Platform `index` at `tick`.
func rect(index: int, tick: int) -> Rect2:
	var out := paths[index].rect_at(tick)
	out.position += origin
	return out


## Every platform at `tick`.
func rects(tick: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in paths.size():
		out.append(rect(i, tick))
	return out


## How far platform `index` moves from `tick` to the next tick, in pixels.
func step_of(index: int, tick: int) -> Vector2:
	return rect(index, tick + 1).position - rect(index, tick).position
