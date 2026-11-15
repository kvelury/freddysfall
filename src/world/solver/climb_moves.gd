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
## - **Moving things.** A hang near a moving platform's track has its jumps and
##   drop tried at every moment of the room's movers (`ReachGraph.phases`), as a
##   ledge near a track has, so a jump timed onto a passing platform counts. A
##   rider (a moving ledge) climbs too: from every moment and stand spot, a held
##   jump straight up off it (a jump leaves the platform's speed behind) is
##   simulated with the movers, and every `SAMPLE` ticks on the way up a lash is
##   tried each way; where one sticks is a hang (`_rider_entries`).
##
## - **Breakable walls** (with `climb_breakable`). A lash that sticks to a
##   breakable wall is a hang like any other (the wall still stands after that
##   first hit) and also its first hit. From it a jump straight off the wall and
##   a lash back at it, once the cooldown is up, is the next hit; since a stick
##   brings back the same hang, any number of hits can be made that way. If that
##   lash lands, the wall breaks (the hit that breaks it does not stick), and
##   where the body is when it does is followed in the copy of the room with the
##   wall broken: a drop from rest, steered, with the air jump if the player has
##   one (`_break_from`). Along the paths from a ceiling, sideways lashes are
##   tried too, but only where the tongue would meet a breakable wall.
##
## It is deliberately a little pessimistic: a hang next to a moving platform's
## whole trip or a spiked path is not counted, nor is a rider's
## lash from anything but a straight-up jump, or a lash from a jump that is not
## straight up from a ledge or a wall hang (except along the paths from a
## ceiling). A breakable
## emitter's sweep does not count as a moving platform once the player has
## Tongue Lash: the player lashes those pillars out of the way.

## The most cells a drop is followed down a wall.
const MAX_DROP := 40
## Ticks after letting go of a ceiling that the spare jump is tried at.
const CEILING_FRAMES: Array[int] = [6, 16]
## The most moments of a room's movers a hang's jumps, or a rider's climb, are
## tried at: `ReachGraph.phases` spread evenly. A hang has many more paths than a
## ledge, so trying every moment of a long trip (a hundred in room 16) multiplies
## the climb's whole cost; fewer moments can only find less.
const CLIMB_PHASES := 12
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
	## The breakable wall it hangs on, or "" for a plain wall or ceiling.
	var wall := ""
	## For a hang on a breakable wall that a lash back at it breaks: what the
	## body comes to in the room with that wall broken, as a ledge of that room.
	var broken_land: ReachGraph.Ledge = null


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
	return "aj%d|%s|%s|%s|c%d|t%d|b%d|cd%s" % [mini(abilities.air_jumps, 1), abilities.tongue_length, abilities.climb_hold, abilities.climb_zip_speed, int(abilities.climb_ceiling), int(abilities.tongue_unlocked), int(abilities.climb_breakable), abilities.tongue_cooldown]


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
	var geo := graph.geometry_of(info)
	var air := graph.abilities.air_jumps > 0
	var ledges := graph._ledges_of(info.id)
	var seen_hangs := {}
	var seen_touches := {}
	var stack: Array = _rider_entries(store, info, geo, ledge) if ledge.moving else _entries(store, info, geo, ledge)
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
		if hang.broken_land != null:
			# The wall it hangs on broken: what follows is in that copy of the room.
			var broken := hang.broken_land
			var copy_ledges := graph._ledges_of(broken.room_id)
			var copy_targets: Array[int] = broken.to_ledges.duplicate()
			if air:
				copy_targets.append_array(broken.air_to_ledges)
			for index in copy_targets:
				var target: ReachGraph.Ledge = copy_ledges[index]
				if not out.ledges.has(target):
					out.ledges.append(target)
			touches.append_array(broken.touches)
			pickups.append_array(broken.pickups)
			if air:
				touches.append_array(broken.air_touches)
				pickups.append_array(broken.air_pickups)
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


## The hangs a rider on moving ledge `ledge` can lash its way into: from every
## moment of the movers and every place it can stand on its stretch, a held
## jump straight up, simulated with the movers (so a rise into a spiked block
## ends there), sampled every `SAMPLE` ticks while it rises, lashing each way.
## The places a lash sticks are kept in the cache (`climb` "r" and the ledge's
## index), since the paths are many.
func _rider_entries(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, ledge: ReachGraph.Ledge) -> Array:
	var entry: SolverCache.Entry = graph.cache.entry_for(info) if graph.cache != null else null
	var key := "r%d" % ledge.index
	var kept: Variant = entry.climb.get(_signature(), {}).get(key) if entry != null else null
	var points: Array = []
	if kept is Dictionary:
		points = kept.get("l", [])
	else:
		points = _rider_points(store, info, geo, ledge)
		if entry != null:
			entry.store_climb_points(_signature(), key, points)
	var out: Array = []
	for point: Array in points:
		var hang := _stick(store, info, geo, Vector2(float(point[0]), float(point[1])), float(point[2]))
		if hang != null and not out.has(hang):
			out.append(hang)
	return out


func _rider_points(store: Store, info: RoomInfo, geo: ReachGraph.Geometry, ledge: ReachGraph.Ledge) -> Array:
	var points: Array = []
	var seen := {}
	var air_frames: Array[int] = [-1]
	if graph.abilities.air_jumps > 0:
		air_frames.append_array(ReachGraph.AIR_RIDE_FRAMES)
	for tick in _climb_phases(info):
		for body in graph._rideable(geo, ledge.path, tick):
			for spot in geo.movers.stand_spots(body, tick):
				if not ReachGraph.in_segment(ledge, spot.x):
					continue
				for frame in air_frames:
					var plan := JumpPlan.new(geo.rects, Vector2(spot.x, spot.y - MovementSim.HALF.y), Vector2.ZERO, 0.0, ReachGraph.HOLDS[-1])
					plan.bounds = geo.bounds
					plan.hazards = geo.hazards
					plan.limit = graph.frame_limit
					plan.record = true
					plan.movers = geo.movers
					plan.start_tick = tick
					plan.start_riding = body
					if frame >= 0:
						plan.air_jumps = 1
						plan.air_frame = frame
						plan.air_hold = CEILING_HOLD
					var run := MovementSim.run(graph._cfg, plan)
					var path: PackedVector2Array = run["path"]
					# A path that dies (a spiked block, spikes) is sampled only up to
					# the tick before.
					var last := path.size() - (2 if bool(run["hazard"]) else 1)
					for i in range(SAMPLE_FROM, last + 1, SAMPLE):
						if i > 0 and path[i].y > path[i - 1].y:
							# Falling again: a lash from here is not a rider's straight-up one.
							break
						var at := path[i].round()
						var box := Rect2(at - MovementSim.HALF, MovementSim.HALF * 2.0).grow(-0.01)
						if _blocked(geo, box) or _unsafe(geo, box):
							continue
						for way in _ways():
							var cell_key := "%d|%d|%d" % [floori(at.x / float(Grid.CELL)), floori(at.y / float(Grid.CELL)), int(way)]
							if seen.has(cell_key):
								continue
							seen[cell_key] = true
							if _stick(store, info, geo, at, way) != null:
								points.append([roundi(at.x), roundi(at.y), int(way)])
	return points


## The moments a jump or drop from `hang` is tried at: every moment of the
## room's movers when it is near a track (`_climb_phases`), or once with none.
func _ticks_for(info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> Array[int]:
	if not geo.movers.is_empty() and graph._near_a_track(geo, hang.land):
		return _climb_phases(info)
	var none: Array[int] = [-1]
	return none


## `ReachGraph.phases`, thinned evenly to at most `CLIMB_PHASES`.
func _climb_phases(info: RoomInfo) -> Array[int]:
	var all := graph.phases(info)
	if all.size() <= CLIMB_PHASES:
		return all
	var out: Array[int] = []
	for i in CLIMB_PHASES:
		out.append(all[i * all.size() / CLIMB_PHASES])
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
	var wall := String(hit["wall"])
	# A breakable wall is stuck to only with `climb_breakable` (the stick is
	# also a hit; `_break_from` follows the next).
	if not bool(hit["solid"]) or (not wall.is_empty() and not abilities.climb_breakable):
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
	if not wall.is_empty():
		key = "w%s|%s" % [wall, key]
	if not store.hangs.has(key):
		var hang := Hang.new()
		hang.key = key
		hang.pos = anchor
		hang.dir = way
		hang.wall = wall
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
		if kept.has("b"):
			_restore_break(info, hang, kept["b"])
		graph.cache.stats["climb_hangs_cached"] += 1
	else:
		var links: Array = []
		if hang.dir == 0.0:
			links = _from_ceiling(info, geo, hang)
			_link_all(store, info, geo, hang, links)
		else:
			_jump_from(info, geo, hang)
		if not hang.wall.is_empty():
			_break_from(info, geo, hang)
		if entry != null:
			entry.store_climb(_signature(), hang.key, land, links, hang.broken_land)
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
	# A path that never comes near a moving thing is the same at every moment:
	# it is sampled once (`_sample` returns true for it).
	var free := {}
	for tick in _ticks_for(info, geo, hang):
		for input in [-1.0, 0.0, 1.0]:
			graph.try_plan(info, geo, land, falls, hang.pos.x, 0.0, input, 0, false, -1, tick, land.top, -1, -1, 0, up)
			var drop_key := "%s|d" % input
			if not free.has(drop_key):
				if _sample(info, geo, store, hang, falls, input, false, -1, 0, points, seen, tick):
					free[drop_key] = true
			for frame in CEILING_FRAMES:
				graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, 1, true, -1, tick, land.top, -1, frame, CEILING_HOLD, up)
				var jump_key := "%s|%d" % [input, frame]
				if not free.has(jump_key):
					if _sample(info, geo, store, hang, near, input, true, frame, CEILING_HOLD, points, seen, tick):
						free[jump_key] = true
	return points


## Runs one path from ceiling hang `hang` and adds to `points` the places along it
## where a lash up sticks. With `tick` 0 or more the movers are in it, from then,
## unless the path without them never comes near one: then that path is the one
## sampled, and it returns true (the path is the same at every moment).
func _sample(info: RoomInfo, geo: ReachGraph.Geometry, store: Store, hang: Hang, rects: Array, input: float, jump: bool, frame: int, air_hold: int, points: Array, seen: Dictionary, tick := -1) -> bool:
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
	var run := MovementSim.run(graph._cfg, plan)
	var free := tick < 0 or not graph._meets_movers(geo, run["bounds"])
	if not free:
		plan.movers = geo.movers
		plan.start_tick = tick
		run = MovementSim.run(graph._cfg, plan)
	var path: PackedVector2Array = run["path"]
	# A path that dies is sampled only up to the tick before.
	var end := path.size() - (1 if bool(run["hazard"]) else 0)
	for i in range(SAMPLE_FROM, end, SAMPLE):
		var at := path[i].round()
		var box := Rect2(at - MovementSim.HALF, MovementSim.HALF * 2.0).grow(-0.01)
		if _blocked(geo, box) or _unsafe(geo, box):
			continue
		for way: float in [0.0, -1.0, 1.0]:
			# Sideways only at a breakable wall: a plain wall would be a wall hang
			# of its own for every sample, which costs far more than it finds.
			if way != 0.0 and not _meets_breakable(info, at, way):
				continue
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
	return free


## The jumps off the wall and the drop from `hang`, simulated as a ledge's are,
## into `hang.land`.
func _jump_from(info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> void:
	var abilities := graph.abilities
	var land := hang.land
	var toward := Vector2(hang.dir, 0.0)
	var inputs: Array[float] = [-hang.dir, 0.0, hang.dir]
	var near := graph._within(geo.rects, Rect2(hang.pos.x - ReachGraph.REACH_X, hang.pos.y - ReachGraph.REACH_UP, ReachGraph.REACH_X * 2.0, ReachGraph.REACH_UP + ReachGraph.REACH_DOWN))
	var falls := graph._near_fall(geo, hang.pos)
	for tick in _ticks_for(info, geo, hang):
		# Near a track the air jumps are the thinned ones a ledge near a track uses.
		var frames := ReachGraph.AIR_FRAMES if tick < 0 else ReachGraph.AIR_RIDE_FRAMES
		var air_holds := ReachGraph.AIR_HOLDS if tick < 0 else ReachGraph.AIR_RIDE_HOLDS
		for input in inputs:
			for hold in ReachGraph.HOLDS:
				graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, hold, true, -1, tick, land.top, -1, -1, 0, toward)
			graph.try_plan(info, geo, land, falls, hang.pos.x, 0.0, input, 0, false, -1, tick, land.top, -1, -1, 0, toward)
			if abilities.air_jumps > 0:
				for hold in ReachGraph.AIR_FIRST_HOLDS:
					for frame in frames:
						for air_hold in air_holds:
							graph.try_plan(info, geo, land, near, hang.pos.x, 0.0, input, hold, true, -1, tick, land.top, -1, frame, air_hold, toward)


## Whether a lash from a body at `center` toward `way` (sideways) first meets a
## breakable wall, with `climb_breakable` on.
func _meets_breakable(info: RoomInfo, center: Vector2, way: float) -> bool:
	if not graph.abilities.climb_breakable or info.breakables.is_empty():
		return false
	var toward := Vector2(way, 0.0)
	return not String(TongueReach.first_hit(info, TongueReach.mouth(center, toward), toward, graph.abilities.tongue_length)["wall"]).is_empty()


## Breaking the breakable wall `hang` hangs on. He jumps straight off it (a
## ground jump, no steer, so he still faces it; for a ceiling, he lets go) and,
## from the tick the cooldown is up, lashes back at it each tick while the path
## lasts: the first lash that meets the same wall is the next hit. A stick
## brings him back to this hang, so the hits repeat until the wall breaks; the
## hit that breaks it does not stick. From where he is at that lash, in the copy
## of the room with the wall broken, a drop from rest (steered left, not at all
## and right, with the air jump if the player has one) is simulated as a
## ledge's is, into `hang.broken_land`.
func _break_from(info: RoomInfo, geo: ReachGraph.Geometry, hang: Hang) -> void:
	var abilities := graph.abilities
	var toward := Vector2(hang.dir, 0.0) if hang.dir != 0.0 else Vector2.UP
	var plan := JumpPlan.new(geo.rects, hang.pos, Vector2.ZERO, 0.0, ReachGraph.HOLDS[-1])
	plan.jump = hang.dir != 0.0
	plan.bounds = geo.bounds
	plan.hazards = geo.hazards
	plan.limit = graph.frame_limit
	plan.hang_dir = toward
	plan.hang_time = abilities.climb_hold
	plan.grounded_start = false
	plan.record = true
	var run := MovementSim.run(graph._cfg, plan)
	var path: PackedVector2Array = run["path"]
	var end := path.size() - (1 if bool(run["hazard"]) else 0)
	var wait := maxi(1, ceili(abilities.tongue_cooldown * float(Mover.TICKS_PER_SECOND)))
	var at := Vector2.INF
	for i in range(wait, end):
		var hit := TongueReach.first_hit(info, TongueReach.mouth(path[i], toward), toward, abilities.tongue_length)
		if String(hit["wall"]) == hang.wall:
			at = path[i]
			break
	if at == Vector2.INF:
		return
	var broken: Array[String] = []
	broken.assign(info.broken)
	broken.append(hang.wall)
	var copy := graph._variant_for(info.base(), broken)
	if copy == null:
		return
	hang.broken_land = _broken_land(copy, at)
	var copy_geo := graph.geometry_of(copy)
	var land := hang.broken_land
	var falls := graph._near_fall(copy_geo, at)
	var near := graph._within(copy_geo.rects, Rect2(at.x - ReachGraph.REACH_X, at.y - ReachGraph.REACH_UP, ReachGraph.REACH_X * 2.0, ReachGraph.REACH_UP + ReachGraph.REACH_DOWN))
	var ticks: Array[int] = [-1]
	if not copy_geo.movers.is_empty() and graph._near_a_track(copy_geo, land):
		ticks = graph.phases(copy)
	for tick in ticks:
		var frames := ReachGraph.AIR_FRAMES if tick < 0 else ReachGraph.AIR_RIDE_FRAMES
		var air_holds := ReachGraph.AIR_HOLDS if tick < 0 else ReachGraph.AIR_RIDE_HOLDS
		for input in [-1.0, 0.0, 1.0]:
			graph.try_plan(copy, copy_geo, land, falls, at.x, 0.0, input, 0, false, -1, tick, land.top)
			if abilities.air_jumps > 0:
				for frame in frames:
					for air_hold in air_holds:
						graph.try_plan(copy, copy_geo, land, near, at.x, 0.0, input, 0, false, -1, tick, land.top, -1, frame, air_hold)


## A ledge of room `copy` standing for a body in the air at `at`.
func _broken_land(copy: RoomInfo, at: Vector2) -> ReachGraph.Ledge:
	var cell := float(Grid.CELL)
	var land := ReachGraph.Ledge.new()
	land.room_id = copy.id
	land.base_id = copy.base()
	land.row = roundi(at.y / cell - 0.5)
	land.top = at.y + cell * 0.5
	land.lo = at.x
	land.hi = at.x
	return land


## `_break_from`'s answer from the cache: {"v": the copy's key, "x", "y": where
## the wall broke, "n", "a": what it reaches}.
func _restore_break(info: RoomInfo, hang: Hang, kept: Dictionary) -> void:
	var broken: Array[String] = []
	broken.assign(info.broken)
	broken.append(hang.wall)
	var copy := graph._variant_for(info.base(), broken)
	if copy == null or copy.id != String(kept.get("v", "")):
		return
	hang.broken_land = _broken_land(copy, Vector2(float(kept["x"]), float(kept["y"])))
	SolverCache.unpack(hang.broken_land, kept["n"], false)
	SolverCache.unpack(hang.broken_land, kept["a"], true)


func _blocked(geo: ReachGraph.Geometry, box: Rect2) -> bool:
	if not geo.bounds.encloses(box):
		return true
	for rect in geo.rects:
		if rect.intersects(box):
			return true
	return false
