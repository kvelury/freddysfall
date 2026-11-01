class_name Movers
extends RefCounted

## A room's moving things as a body sees them: every body of every mover as one
## flat list with a stable index, shifted to where the room is. The game gives
## it the room's position, the solver works in room pixels and leaves it at
## zero. A body can be gone at a tick (an emitted platform that has broken), and
## can be a hazard (a spiked block) that kills on touch instead of holding up.

var paths: Array[Mover] = []
var origin := Vector2.ZERO
## Where every body is at a tick, worked out once: the solver asks again and again.
## Dropped when it gets big, which only the running game reaches.
const CACHE_LIMIT := 4096
var _cache := {}
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


## Everything about the bodies at `tick`, worked out once: each body's rect and
## whether it is there, and the solid and the spiked rects among them.
func _at(tick: int) -> Dictionary:
	var found: Variant = _cache.get(tick)
	if found != null:
		return found
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	var rects_now: Array[Rect2] = []
	var there: Array[bool] = []
	var solid: Array[Rect2] = []
	var spiked: Array[Rect2] = []
	for i in size():
		var mover := paths[_owner[i]]
		var present := mover.alive_at(tick, _local[i])
		var box := mover.rect_at(tick, _local[i])
		box.position += origin
		rects_now.append(box)
		there.append(present)
		if present:
			if mover.is_hazard(_local[i]):
				spiked.append(box)
			else:
				solid.append(box)
	var entry := {"rects": rects_now, "alive": there, "solid": solid, "hazard": spiked}
	_cache[tick] = entry
	return entry


## Body `index` at `tick`. Check `alive` first for a body that can go.
func rect(index: int, tick: int) -> Rect2:
	return _at(tick)["rects"][index]


## Whether body `index` exists at `tick`.
func alive(index: int, tick: int) -> bool:
	return _at(tick)["alive"][index]


## Whether body `index` kills on touch.
func hazard(index: int) -> bool:
	return paths[_owner[index]].is_hazard(_local[index])


## The bodies that hold a player up, where they are at `tick`: solid, there,
## and not hazards.
func rects(tick: int) -> Array[Rect2]:
	return _at(tick)["solid"]


## The hazard bodies at `tick`.
func hazard_rects(tick: int) -> Array[Rect2]:
	return _at(tick)["hazard"]


## How far body `index` moves from `tick` to the next tick, in pixels. A body
## that is not there at both ends does not carry or push.
func step_of(index: int, tick: int) -> Vector2:
	if not alive(index, tick) or not alive(index, tick + 1) or not paths[_owner[index]].continuous_at(tick, _local[index]):
		return Vector2.ZERO
	return rect(index, tick + 1).position - rect(index, tick).position
