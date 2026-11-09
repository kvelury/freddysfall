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


## Everything about the bodies at `tick`, worked out once: each body's box and
## whether it is there, and the solid and the spiked rects among them. A turned
## body is many rects (rows of pixels, `Mover.spans_at`): those are also kept by
## row, so a body can ask for the few that are near it.
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
	var plain_solid: Array[Rect2] = []
	var plain_spiked: Array[Rect2] = []
	var rows_solid := {}
	var rows_spiked := {}
	var owner := {}
	for i in size():
		var mover := paths[_owner[i]]
		var present := mover.alive_at(tick, _local[i])
		var box := mover.rect_at(tick, _local[i])
		box.position += origin
		rects_now.append(box)
		there.append(present)
		if not present:
			continue
		var hazard := mover.is_hazard(_local[i])
		if not mover.smooth():
			if hazard:
				spiked.append(box)
				plain_spiked.append(box)
			else:
				solid.append(box)
				plain_solid.append(box)
				owner[box] = i
			continue
		for run in mover.spans_at(tick, _local[i]):
			var placed := Rect2(run.position + origin, run.size)
			var row := floori(placed.position.y)
			if hazard:
				spiked.append(placed)
				if not rows_spiked.has(row):
					rows_spiked[row] = [] as Array[Rect2]
				rows_spiked[row].append(placed)
			else:
				solid.append(placed)
				if not rows_solid.has(row):
					rows_solid[row] = [] as Array[Rect2]
				rows_solid[row].append(placed)
				owner[placed] = i
	var entry := {"rects": rects_now, "alive": there, "solid": solid, "hazard": spiked, "plain_solid": plain_solid, "plain_hazard": plain_spiked, "rows_solid": rows_solid, "rows_hazard": rows_spiked, "owner": owner}
	_cache[tick] = entry
	return entry


## Body `index` at `tick`: its box, round every pixel of it if it is a turned
## one. Check `alive` first for a body that can go.
func rect(index: int, tick: int) -> Rect2:
	return _at(tick)["rects"][index]


## Whether body `index` exists at `tick`.
func alive(index: int, tick: int) -> bool:
	return _at(tick)["alive"][index]


## Whether body `index` kills on touch.
func hazard(index: int) -> bool:
	return paths[_owner[index]].is_hazard(_local[index])


## Whether body `index` is a turned shape (see `Mover.smooth`).
func smooth(index: int) -> bool:
	return paths[_owner[index]].smooth()


## The bodies that hold a player up, where they are at `tick`: solid, there,
## and not hazards.
func rects(tick: int) -> Array[Rect2]:
	return _at(tick)["solid"]


## The solid rects at `tick` that a box `near` could touch: every box that is
## one body, and of the rows of pixels only those in `near`'s rows.
func rects_near(tick: int, near: Rect2) -> Array[Rect2]:
	var entry := _at(tick)
	if (entry["rows_solid"] as Dictionary).is_empty():
		return entry["plain_solid"]
	var out: Array[Rect2] = entry["plain_solid"].duplicate()
	_gather(entry["rows_solid"], near, out)
	return out


## The rows of pixels of turned bodies at `tick` that a box `near` could touch.
func smooth_near(tick: int, near: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	_gather(_at(tick)["rows_solid"], near, out)
	return out


## The spiked rects at `tick` that a box `near` could touch.
func hazards_near(tick: int, near: Rect2) -> Array[Rect2]:
	var entry := _at(tick)
	if (entry["rows_hazard"] as Dictionary).is_empty():
		return entry["plain_hazard"]
	var out: Array[Rect2] = entry["plain_hazard"].duplicate()
	_gather(entry["rows_hazard"], near, out)
	return out


static func _gather(rows: Dictionary, near: Rect2, out: Array[Rect2]) -> void:
	for y in range(floori(near.position.y), ceili(near.end.y)):
		var list: Variant = rows.get(y)
		if list == null:
			continue
		for run: Rect2 in list:
			if run.position.x < near.end.x and run.end.x > near.position.x:
				out.append(run)


## The body that the solid rect `rect` is part of at `tick`, or -1.
func body_under(box: Rect2, tick: int) -> int:
	return _at(tick)["owner"].get(box, -1)


## The index in `paths` of a breakable mover with a body that holds a player up
## and touches `box` at `tick`, or -1. This is what a lash can hit.
func breakable_at(box: Rect2, tick: int) -> int:
	for m in paths.size():
		if not paths[m] is SpinnerPath or not (paths[m] as SpinnerPath).breakable:
			continue
		var first := first_body(m)
		for b in paths[m].body_count():
			if not alive(first + b, tick) or hazard(first + b) or not rect(first + b, tick).intersects(box):
				continue
			for run in paths[m].spans_at(tick, b):
				if Rect2(run.position + origin, run.size).intersects(box):
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
				for run in paths[m].spans_at(tick, b):
					rects_here.append(Rect2(run.position + origin, run.size))
		if not rects_here.is_empty():
			out[paths[m].id] = rects_here
	return out


## The hazard bodies at `tick`.
func hazard_rects(tick: int) -> Array[Rect2]:
	return _at(tick)["hazard"]


## How far body `index` moves from `tick` to the next tick, in pixels, for a
## body that is one box. A body that is not there at both ends does not carry or
## push.
func step_of(index: int, tick: int) -> Vector2:
	if not alive(index, tick) or not alive(index, tick + 1) or not paths[_owner[index]].continuous_at(tick, _local[index]):
		return Vector2.ZERO
	return rect(index, tick + 1).position - rect(index, tick).position


## How far a body standing at `point` is carried by body `index` from `tick` to
## `tick + 1`: its step, or for a turning body the point going round.
func carry_of(index: int, tick: int, point: Vector2) -> Vector2:
	if not alive(index, tick) or not alive(index, tick + 1) or not paths[_owner[index]].continuous_at(tick, _local[index]):
		return Vector2.ZERO
	return paths[_owner[index]].carry_at(tick, _local[index], point - origin)


## How far a box centred on `centre` has to go to leave body `index` at `tick`,
## or `Vector2.INF` for a body that has no exact shape.
func push_of(index: int, tick: int, centre: Vector2) -> Vector2:
	return paths[_owner[index]].push_at(tick, _local[index], centre - origin)


## Whether a body can stand on body `index` at `tick` (see `Mover.rideable_at`).
func rideable(index: int, tick: int) -> bool:
	return paths[_owner[index]].rideable_at(tick, _local[index])


## Where a rider can stand on body `index` at `tick`, as (x of its centre, y of
## the top it stands on), in room pixels. A spot a body would be inside of
## another body at is left out.
func stand_spots(index: int, tick: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not alive(index, tick):
		return out
	var mover := paths[_owner[index]]
	for spot in mover.stand_spots(tick, _local[index]):
		var at := spot + origin
		if not mover.smooth():
			out.append(at)
			continue
		var feet := Rect2(at.x - 5.0, at.y - 10.0, 10.0, 10.0).grow(-0.01)
		var blocked := false
		for run in rects_near(tick, feet):
			if run.intersects(feet) and body_under(run, tick) != index:
				blocked = true
				break
		if not blocked:
			for run in hazards_near(tick, feet):
				if run.intersects(feet):
					blocked = true
					break
		if not blocked:
			out.append(at)
	return out
