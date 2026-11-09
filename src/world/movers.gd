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
## Ticks after which every mover is back where it started (the least common
## multiple of their periods), so the cache is kept by `tick % _period`. 0 when
## that is longer than CACHE_LIMIT, and the cache is kept by tick.
var _period := 0


func _init(list: Array[Mover] = [], at := Vector2.ZERO) -> void:
	# Its own list: a mover that breaks is swapped out here (see `replace`), and
	# the room's list must stay as loaded for the next time the room is built.
	paths = list.duplicate()
	origin = at
	for p in paths.size():
		for b in paths[p].body_count():
			_owner.append(p)
			_local.append(b)
	var together := 1
	for mover in paths:
		var period := maxi(1, mover.period())
		together = together / _gcd(together, period) * period
		if together > CACHE_LIMIT:
			together = 0
			break
	_period = together


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var r := a % b
		a = b
		b = r
	return a


func size() -> int:
	return _owner.size()


## Swaps mover `m` for `other`, which has the same bodies (a breakable spinner
## for its broken copy), and forgets where everything was.
func replace(m: int, other: Mover) -> void:
	paths[m] = other
	_cache.clear()


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
	# Every mover repeats exactly after its period (tests/mover_test.gd).
	if _period > 0:
		tick = posmod(tick, _period)
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


## The index in `paths` of a breakable mover with a body that holds a player up
## and touches `box` at `tick`, or -1. This is what a lash can hit.
func breakable_at(box: Rect2, tick: int) -> int:
	for m in paths.size():
		if not paths[m] is SpinnerPath or not (paths[m] as SpinnerPath).breakable:
			continue
		var first := first_body(m)
		for b in paths[m].body_count():
			if alive(first + b, tick) and not hazard(first + b) and rect(first + b, tick).intersects(box):
				return m
	return -1


## The solid bodies of each breakable mover that stands, by its id, at `tick`: what
## the solver's tongue tests against (TongueReach.first_hit).
func breakable_rects(tick: int) -> Dictionary:
	var out := {}
	for m in paths.size():
		if not paths[m] is SpinnerPath or not (paths[m] as SpinnerPath).breakable:
			continue
		var rects_here: Array[Rect2] = []
		var first := first_body(m)
		for b in paths[m].body_count():
			if alive(first + b, tick) and not hazard(first + b):
				rects_here.append(rect(first + b, tick))
		if not rects_here.is_empty():
			out[paths[m].id] = rects_here
	return out


## The hazard bodies at `tick`.
func hazard_rects(tick: int) -> Array[Rect2]:
	return _at(tick)["hazard"]


## How far body `index` moves from `tick` to the next tick, in pixels. A body
## that is not there at both ends does not carry or push.
func step_of(index: int, tick: int) -> Vector2:
	if not alive(index, tick) or not alive(index, tick + 1) or not paths[_owner[index]].continuous_at(tick, _local[index]):
		return Vector2.ZERO
	return rect(index, tick + 1).position - rect(index, tick).position
