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
## - **Ceilings** (with `climb_ceiling`). The same body lashing straight up, from a
##   ledge's column or a wall hang's, at a plain ceiling within `tongue_length`
##   hangs from it (`MovementSim.start_climb` going up). From a ceiling hang the
##   drop is simulated, steered left, not at all or right, and so is jump (which
##   lets go) followed by the spare jump at `CEILING_FRAMES`, held `CEILING_HOLD`;
##   the spare jump needs no double jump. Every `SAMPLE` ticks along those paths
##   the body lashes up again, and where it sticks is a new hang (one per cell
##   of ceiling). Sideways lashes from those paths are not tried: each would
##   be a wall hang of its own, which costs far more than it finds. Those places are kept in the cache with the hang.
##
## It is deliberately a little pessimistic: a hang next to a moving platform or
## a spiked path is not counted, nor is a breakable wall, a hang on a moving
## platform's rider, or a lash from a jump that is not straight up from a ledge
## or a wall hang (except along the paths from a ceiling). A breakable
## emitter's sweep does not count as a moving platform once the player has
## Tongue Lash: the player lashes those pillars out of the way.

## The most cells a drop is followed down a wall.
const MAX_DROP := 40
## Ticks after letting go of a ceiling that the spare jump is tried at.
const CEILING_FRAMES: Array[int] = [6, 16]
## How long the spare jump is held: all the way.
const CEILING_HOLD := 90
## Ticks between the places along a path from a ceiling where a lash is tried,
## and the first of them.
const SAMPLE := 4
const SAMPLE_FROM := 4

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
	## The wall's side (-1, 1), or 0 for a ceiling.
	var dir := 1.0
	var expanded := false
	## The hangs a hop up or a fall from here, and then a stick, can reach.
	var links: Array = []
	## What its jumps and drop land on, touch and take, kept as a ledge's are.
	var land: ReachGraph.Ledge = null


class Store extends RefCounted:
	var hangs := {}
	var sticks := {}
	## Cell and way along a path from a ceiling -> [x, y, way] of the first lash
	## tried there that sticks, or [] for none: shared by every ceiling hang.
	var sampled := {}
	var moves := {}


## What a hang's answers depend on besides the room: the one air jump the solver
## models, and the stats that decide where the tongue sticks and how long he hangs.
func _signature() -> String:
	var abilities := graph.abilities
	return "aj%d|%s|%s|%s|c%d|t%d" % [mini(abilities.air_jumps, 1), abilities.tongue_length, abilities.climb_hold, abilities.climb_zip_speed, int(abilities.climb_ceiling), int(abilities.tongue_unlocked)]


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
			for way in _ways():
				var hang := _stick(store, info, geo, center, way)
				if hang != null and not out.has(hang):
					out.append(hang)
	return out


## The ways a lash is tried: to either side, and up with `climb_ceiling`.
func _ways() -> Array[float]:
	if graph.abilities.climb_ceiling:
		return [-1.0, 1.0, 0.0]
	return [-1.0, 1.0]


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
	var toward := Vector2(way, 0.0) if way != 0.0 else Vector2.UP
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
	if way == 0.0:
		# One hang per cell of ceiling: the first place found under it stands for
		# the cell, so the paths from a ceiling do not multiply hangs pixel by pixel.
		key = "c%d|%d" % [floori(anchor.x / float(Grid.CELL)), roundi(anchor.y)]
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
## A breakable emitter's sweep does not count once the player has Tongue Lash.
func _unsafe(geo: ReachGraph.Geometry, box: Rect2) -> bool:
	for rect in geo.hazards:
		if rect.intersects(box):
			return true
	for m in geo.mover_space.size():
		if graph.abilities.tongue_unlocked and m < geo.movers.paths.size() and geo.movers.paths[m] is EmitterPath and (geo.movers.paths[m] as EmitterPath).breakable:
			continue
		if geo.mover_space[m].grow(float(Grid.CELL)).intersects(box):
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
		if hang.dir == 0.0:
			_link_all(store, info, geo, hang, kept.get("l", []))
		graph.cache.stats["climb_hangs_cached"] += 1
	else:
		var links: Array = []
		if hang.dir == 0.0:
			links = _from_ceiling(info, geo, hang)
			_link_all(store, info, geo, hang, links)
		else:
			_jump_from(info, geo, hang)
		if entry != null:
			entry.store_climb(_signature(), hang.key, land, links)
			graph.cache.stats["climb_hangs_solved"] += 1
	if hang.dir == 0.0:
		return
	# Up the wall, or down it: a body in the clear column lashes again.
	var up := maxi(0, graph._rise_cells(1 if abilities.air_jumps > 0 else 0) - 1)
	for step in [-1, 1]:
		var limit := up if step < 0 else MAX_DROP
		for j in range(1, limit + 1):
			var center := hang.pos + Vector2(0.0, float(step * j) * cell)
			var box := Rect2(center - MovementSim.HALF, MovementSim.HALF * 2.0).grow(-0.01)
			if _blocked(geo, box) or _unsafe(geo, box):
				break
			for way in _ways():
				var other := _stick(store, info, geo, center, way)
				if other != null and other != hang and not hang.links.has(other):
					hang.links.append(other)


## The hangs that lashes from `points` ([x, y, way], whole pixels) stick at.
func _link_all(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang, points: Array) -> void:
	for point: Array in points:
		var other := _stick(store, info, geo, Vector2(float(point[0]), float(point[1])), float(point[2]))
		if other != null and other != hang and not hang.links.has(other):
			hang.links.append(other)


## Letting go of ceiling hang `hang`: the drop, and jump (letting go) then the
## spare jump, each steered left, not at all and right, simulated as a ledge's
## jumps are, into `hang.land`. Returns the places along those paths where a
## lash sticks ([x, y, way] in whole pixels), for `_link_all`.
func _from_ceiling(info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> Array:
	var land := hang.land
	var up := Vector2.UP
	var near := graph._within(geo.rects, Rect2(hang.pos.x - ReachGraph.REACH_X, hang.pos.y - ReachGraph.REACH_UP, ReachGraph.REACH_X * 2.0, ReachGraph.REACH_UP + ReachGraph.REACH_DOWN))
	var falls := graph._near_fall(geo, hang.pos)
	var store := _store(info)
	var points: Array = []
	var seen := {}
	for input in [-1.0, 0.0, 1.0]:
		graph.try_plan(info, geo, land, falls, hang.pos.x, 0.0, input, 0, false, -1, -1, land.top, -1, -1, 0, up)
		_sample(info, geo, store, hang, falls, input, false, -1, 0, points, seen)
		for frame in CEILING_FRAMES:
			graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, 1, true, -1, -1, land.top, -1, frame, CEILING_HOLD, up)
			_sample(info, geo, store, hang, near, input, true, frame, CEILING_HOLD, points, seen)
	return points


## Runs one path from ceiling hang `hang` and adds to `points` the places along it
## where a lash up sticks.
func _sample(info: RoomInfo, geo: ReachGraph.Geometry, store: Store, hang: Hang, rects: Array, input: float, jump: bool, frame: int, air_hold: int, points: Array, seen: Dictionary) -> void:
	var plan := JumpPlan.new(rects, hang.pos, Vector2.ZERO, input, 1 if jump else 0)
	plan.jump = jump
	plan.bounds = geo.bounds
	plan.hazards = geo.hazards
	plan.limit = graph.frame_limit
	plan.hang_dir = Vector2.UP
	plan.hang_time = graph.abilities.climb_hold
	plan.grounded_start = false
	plan.record = true
	if frame >= 0:
		plan.air_jumps = 1
		plan.air_frame = frame
		plan.air_hold = air_hold
	var path: PackedVector2Array = MovementSim.run(graph._cfg, plan)["path"]
	for i in range(SAMPLE_FROM, path.size(), SAMPLE):
		var at := path[i].round()
		var box := Rect2(at - MovementSim.HALF, MovementSim.HALF * 2.0).grow(-0.01)
		if _blocked(geo, box) or _unsafe(geo, box):
			continue
		for way: float in [0.0]:
			# Once per cell along the paths from every ceiling hang: a lash a pixel
			# over is the same, and the first tried there stands for the cell.
			var key := "%d|%d|%d" % [floori(at.x / float(Grid.CELL)), floori(at.y / float(Grid.CELL)), int(way)]
			if seen.has(key):
				continue
			seen[key] = true
			if not store.sampled.has(key):
				var other := _stick(store, info, geo, at, way)
				store.sampled[key] = [roundi(at.x), roundi(at.y), int(way)] if other != null else []
			var point: Array = store.sampled[key]
			if not point.is_empty() and _stick(store, info, geo, Vector2(float(point[0]), float(point[1])), float(point[2])) != hang:
				points.append(point)


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
