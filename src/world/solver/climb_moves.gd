class_name ClimbMoves
extends MoveProvider

## Tongue Climb: a lash that sticks to a plain wall pulls Freddy to it and he
## hangs there, with his jumps back. The solver treats a hang as a place with
## its own jumps, in two parts:
##
## - **Getting there.** From a ledge, a body that jumps straight up can lash
##   sideways at any height it reaches (`_rise_cells`, as the lash does for a
##   breakable wall). If the tip meets a plain wall within `tongue_length`,
##   `MovementSim.start_climb` says where he hangs, so the solver and the game
##   agree to the pixel. From a hang the same thing, one cell step at a time
##   up (no further than a jump off the wall rises, less one cell), or down
##   (a fall, as far as the column stays clear), is a new hang, on either wall.
## - **Leaving.** From each hang the jumps are simulated as from a ledge:
##   a ground jump off the wall, with the double jump if the player has one, in
##   each direction, and a drop. What they land on, touch or take counts.
##
## It is deliberately a little pessimistic: a hang next to a moving platform or
## a spiked path is not counted, nor is a ceiling hang, a breakable wall, or a
## hang on a moving platform's rider.

## The most cells a drop is followed down a wall.
const MAX_DROP := 40

## room key + what the answer depends on -> Store.
var _stores := {}


func key() -> String:
	return "climb"


func applies(abilities: Abilities) -> bool:
	return abilities != null and abilities.tongue_unlocked and abilities.tongue_climb


func next(ledge: ReachGraph.Ledge, info: RoomInfo, _run: ReachGraph.Run) -> MoveProvider.Moves:
	return _moves_of(ledge, info)


func picked(ledge: ReachGraph.Ledge, _run: ReachGraph.Run, index: int) -> bool:
	return _moves_of(ledge, graph._info_of(ledge.room_id)).pickups.has(index)


## One hang: where the body's centre is, and the wall it is on.
class Hang extends RefCounted:
	var key := ""
	var pos := Vector2.ZERO
	var dir := 1.0
	var expanded := false
	## The hangs a hop up or a fall from here, and then a stick, can reach.
	var links: Array = []
	## What its jumps and drop land on, touch and take, kept as a ledge's are.
	var land: ReachGraph.Ledge = null


class Store extends RefCounted:
	var hangs := {}
	var sticks := {}
	var moves := {}


## What a hang's answers depend on besides the room: the one air jump the solver
## models, and the stats that decide where the tongue sticks and how long he hangs.
func _signature() -> String:
	var abilities := graph.abilities
	return "aj%d|%s|%s|%s" % [mini(abilities.air_jumps, 1), abilities.tongue_length, abilities.climb_hold, abilities.climb_zip_speed]


func _store(info: RoomInfo) -> Store:
	var key := "%s|%s" % [info.id, _signature()]
	if not _stores.has(key):
		_stores[key] = Store.new()
	return _stores[key]


## What standing on `ledge` can get to by hanging: everything the hangs it can
## reach lead to.
func _moves_of(ledge: ReachGraph.Ledge, info: RoomInfo) -> MoveProvider.Moves:
	var store := _store(info)
	if store.moves.has(ledge):
		return store.moves[ledge]
	var out := MoveProvider.Moves.new()
	store.moves[ledge] = out
	if ledge.moving:
		return out
	var geo := graph.geometry_of(info)
	var air := graph.abilities.air_jumps > 0
	var ledges := graph._ledges_of(info.id)
	var seen_hangs := {}
	var seen_touches := {}
	var stack: Array = _entries(store, info, geo, ledge)
	while not stack.is_empty():
		var hang: Hang = stack.pop_back()
		if seen_hangs.has(hang):
			continue
		seen_hangs[hang] = true
		_expand(store, info, geo, hang)
		stack.append_array(hang.links)
		var targets: Array[int] = hang.land.to_ledges.duplicate()
		var touches: Array[ReachGraph.Touch] = hang.land.touches.duplicate()
		var pickups: Array[int] = hang.land.pickups.duplicate()
		if air:
			targets.append_array(hang.land.air_to_ledges)
			touches.append_array(hang.land.air_touches)
			pickups.append_array(hang.land.air_pickups)
		for index in targets:
			var target: ReachGraph.Ledge = ledges[index]
			if target != ledge and not out.ledges.has(target):
				out.ledges.append(target)
		for touch in touches:
			if not seen_touches.has(touch.key()):
				seen_touches[touch.key()] = true
				out.touches.append(touch)
		for index in pickups:
			if not out.pickups.has(index):
				out.pickups.append(index)
	return out


## The hangs a body that jumps straight up from `ledge` can lash its way into.
func _entries(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, ledge: ReachGraph.Ledge) -> Array:
	var out: Array = []
	var cell := float(Grid.CELL)
	var rise := graph._rise_cells(1 if graph.abilities.air_jumps > 0 else 0)
	for cx in range(ledge.x0, ledge.x1 + 1):
		for height in rise + 1:
			var row := ledge.row - height
			if row < 0 or info.is_solid(cx, row):
				break
			if info.is_hazard(cx, row):
				continue
			var center := Vector2((float(cx) + 0.5) * cell, (float(row) + 0.5) * cell)
			for way in [-1.0, 1.0]:
				var hang := _stick(store, info, geo, center, way)
				if hang != null and not out.has(hang):
					out.append(hang)
	return out


## Where a body in the air at `center` that lashes toward `way` hangs, or null
## if the tongue does not stick to a plain wall, or the pull is not clean.
func _stick(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, center: Vector2, way: float) -> Hang:
	var key := "%d|%d|%d" % [roundi(center.x * 10.0), roundi(center.y * 10.0), int(way)]
	if store.sticks.has(key):
		return store.sticks[key]
	var found := _try_stick(store, info, geo, center, way)
	store.sticks[key] = found
	return found


func _try_stick(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, center: Vector2, way: float) -> Hang:
	var abilities := graph.abilities
	var toward := Vector2(way, 0.0)
	var hit := TongueReach.first_hit(info, TongueReach.mouth(center, toward), toward, abilities.tongue_length)
	# A breakable wall is not stuck to here: it is a state of the room, and the
	# lash provider owns those.
	if not bool(hit["solid"]) or not String(hit["wall"]).is_empty():
		return null
	var reach := abilities.tongue_length + 30.0
	var near := graph._within(geo.rects, Rect2(center - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))
	var state := MovementSim.State.new()
	state.position = center
	if not MovementSim.start_climb(state, near, hit["at"], toward, abilities.climb_hold, abilities.climb_zip_speed, false) or state.climb_abort:
		return null
	var anchor := state.climb_anchor
	var swept := Rect2(center - MovementSim.HALF, MovementSim.HALF * 2.0).merge(Rect2(anchor - MovementSim.HALF, MovementSim.HALF * 2.0)).grow(-0.01)
	if not geo.bounds.has_point(anchor) or _unsafe(geo, swept):
		return null
	var key := "%d|%d|%d" % [roundi(anchor.x), roundi(anchor.y), int(way)]
	if not store.hangs.has(key):
		var hang := Hang.new()
		hang.key = key
		hang.pos = anchor
		hang.dir = way
		store.hangs[key] = hang
	return store.hangs[key]


## Works out every hang the room has, so the cache has them: what each ledge
## can reach by climbing, for the room as it is now.
func warm(info: RoomInfo) -> void:
	for ledge: ReachGraph.Ledge in graph._ledges_of(info.id):
		_moves_of(ledge, info)


## Whether a body in `box` is on spikes or near a moving platform's whole trip.
func _unsafe(geo: ReachGraph.Geometry, box: Rect2) -> bool:
	for rect in geo.hazards:
		if rect.intersects(box):
			return true
	for space in geo.mover_space:
		if space.grow(float(Grid.CELL)).intersects(box):
			return true
	return false


## Works out what jumping off, dropping from, and moving along the wall from
## `hang` comes to. Done once for each.
func _expand(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> void:
	if hang.expanded:
		return
	hang.expanded = true
	var abilities := graph.abilities
	var cell := float(Grid.CELL)
	var land := ReachGraph.Ledge.new()
	land.room_id = info.id
	land.base_id = info.base()
	land.row = roundi(hang.pos.y / cell - 0.5)
	land.top = hang.pos.y + cell * 0.5
	land.lo = hang.pos.x
	land.hi = hang.pos.x
	hang.land = land
	var entry: SolverCache.Entry = graph.cache.entry_for(info) if graph.cache != null else null
	var kept: Variant = entry.climb.get(_signature(), {}).get(hang.key) if entry != null else null
	if kept is Dictionary:
		SolverCache.unpack(land, kept["n"], false)
		SolverCache.unpack(land, kept["a"], true)
		graph.cache.stats["climb_hangs_cached"] += 1
	else:
		_jump_from(info, geo, hang)
		if entry != null:
			entry.store_climb(_signature(), hang.key, land)
			graph.cache.stats["climb_hangs_solved"] += 1
	# Up the wall, or down it: a body in the clear column lashes again.
	var up := maxi(0, graph._rise_cells(1 if abilities.air_jumps > 0 else 0) - 1)
	for step in [-1, 1]:
		var limit := up if step < 0 else MAX_DROP
		for j in range(1, limit + 1):
			var center := hang.pos + Vector2(0.0, float(step * j) * cell)
			var box := Rect2(center - MovementSim.HALF, MovementSim.HALF * 2.0).grow(-0.01)
			if _blocked(geo, box) or _unsafe(geo, box):
				break
			for way in [-1.0, 1.0]:
				var other := _stick(store, info, geo, center, way)
				if other != null and other != hang and not hang.links.has(other):
					hang.links.append(other)


## The jumps off the wall and the drop from `hang`, simulated as a ledge's are,
## into `hang.land`.
func _jump_from(info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> void:
	var abilities := graph.abilities
	var land := hang.land
	var toward := Vector2(hang.dir, 0.0)
	var inputs: Array[float] = [-hang.dir, 0.0, hang.dir]
	var near := graph._within(geo.rects, Rect2(hang.pos.x - ReachGraph.REACH_X, hang.pos.y - ReachGraph.REACH_UP, ReachGraph.REACH_X * 2.0, ReachGraph.REACH_UP + ReachGraph.REACH_DOWN))
	var falls := graph._near_fall(geo, hang.pos)
	for input in inputs:
		for hold in ReachGraph.HOLDS:
			graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, hold, true, -1, -1, land.top, -1, -1, 0, toward)
		graph.try_plan(info, geo, land, falls, hang.pos.x, 0.0, input, 0, false, -1, -1, land.top, -1, -1, 0, toward)
		if abilities.air_jumps > 0:
			for hold in ReachGraph.AIR_FIRST_HOLDS:
				for frame in ReachGraph.AIR_FRAMES:
					for air_hold in ReachGraph.AIR_HOLDS:
						graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, hold, true, -1, -1, land.top, -1, frame, air_hold, toward)


func _blocked(geo: ReachGraph.Geometry, box: Rect2) -> bool:
	if not geo.bounds.encloses(box):
		return true
	for rect in geo.rects:
		if rect.intersects(box):
			return true
	return false
