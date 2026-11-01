class_name Movers
extends RefCounted

## A room's moving things as a body sees them: every body of every mover as one
## flat list with a stable index, shifted to where the room is. The game gives
## it the room's position, the solver works in room pixels and leaves it at
## zero. A body can be gone at a tick (an emitted platform that has broken), and
## can be a hazard (a spiked block) that kills on touch instead of holding up.

var paths: Array[Mover] = []
var origin := Vector2.ZERO
var _owner: PackedInt32Array = PackedInt32Array()
var _local: PackedInt32Array = PackedInt32Array()


func _init(list: Array[Mover] = [], at := Vector2.ZERO) -> void:
	paths = list
	origin = at
	for p in paths.size():
		for b in paths[p].body_count():
			_owner.append(p)
			_local.append(b)


func size() -> int:
	return _owner.size()


func is_empty() -> bool:
	return _owner.is_empty()


## Which mover (an index into `paths`) body `index` belongs to.
func mover_of(index: int) -> int:
	return _owner[index]


## The index of mover `m`'s first body.
func first_body(m: int) -> int:
	var at := 0
	for i in m:
		at += paths[i].body_count()
	return at


## Body `index` at `tick`. Check `alive` first for a body that can go.
func rect(index: int, tick: int) -> Rect2:
	var out := paths[_owner[index]].rect_at(tick, _local[index])
	out.position += origin
	return out


## Whether body `index` exists at `tick`.
func alive(index: int, tick: int) -> bool:
	return paths[_owner[index]].alive_at(tick, _local[index])


## Whether body `index` kills on touch.
func hazard(index: int) -> bool:
	return paths[_owner[index]].is_hazard(_local[index])


## The bodies that hold a player up, where they are at `tick`: solid, there,
## and not hazards.
func rects(tick: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in size():
		if not hazard(i) and alive(i, tick):
			out.append(rect(i, tick))
	return out


## The hazard bodies at `tick`.
func hazard_rects(tick: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in size():
		if hazard(i) and alive(i, tick):
			out.append(rect(i, tick))
	return out


## How far body `index` moves from `tick` to the next tick, in pixels. A body
## that is not there at both ends does not carry or push.
func step_of(index: int, tick: int) -> Vector2:
	if not alive(index, tick) or not alive(index, tick + 1) or not paths[_owner[index]].continuous_at(tick, _local[index]):
		return Vector2.ZERO
	return rect(index, tick + 1).position - rect(index, tick).position
