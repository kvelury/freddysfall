class_name ImprintSearch
extends RefCounted

## The part of the solver that knows about Imprint. A player standing on a
## ledge can put a platform down and then jump: first onto the platform, then
## from it to somewhere the ledge alone could not reach. This finds those
## places.
##
## It does not try every platform. Jumps are simulated from the ledge once, and
## a platform is only a candidate where one of those jumps comes down through
## the top of a cell row. Each candidate is checked by simulating the jump
## again with the platform in place, and then kept only if it brings one of
## the places still out of reach within a jump. The jumps from the platform use
## the same tries as any ledge. The platform has to last until the player has
## landed on it and pushed off (see SPARE_TICKS); after that it is not needed.
##
## A placed platform shrinks one block at a time, in an order fixed when it is
## placed: the block nearest where the player stood goes last. The player places
## from the ledge, at the start of the jump, so the footing the solver counts on
## is the block nearest the arc's start, which stands for the whole life. When
## two blocks are as near, the player's facing decides, and they can turn either
## way before clicking, so either block counts. The whole platform is still what
## has to be legal to place, but the jump must land on the last block, and must
## land there just the same with the other blocks gone. Legs, the places a body
## standing on the platform can get to, start from the last block alone.
##
## What it leaves out: placing the platform in mid-air, and using two in a row.
## A room that needs either is reported unreachable even though a player might
## do it. It does not see moving platforms either: it puts no Imprint down
## from one, and its jumps pass through them. It leaves out landing on an outer
## block while it stands, and walking off onto outer blocks while they stand.
## Classic mode is not modelled either; it has strictly more footing, so
## validation is conservative for it.

## The jump onto a platform has to land within the platform's life less this
## many ticks, to stand on it and push off. The jump off it is an ordinary
## ledge's: once the player has left it, they no longer need it.
const SPARE_TICKS := 40
## At most this many platforms are tried from one ledge.
const MAX_CANDIDATES := 600
## Verifications that land on a platform from one ledge, per platform.
const MAX_ARCS_PER_CANDIDATE := 6

var _graph: ReachGraph
var _arcs := {}
var _legs := {}
## Where the time goes, in microseconds, and how many platforms were looked at:
## "arcs", "lands" and "legs", "candidates", and "legs_made".
var stats := {"arcs": 0, "lands": 0, "legs": 0, "candidates": 0, "legs_made": 0}


func _init(graph: ReachGraph) -> void:
	_graph = graph


## What a platform put down from `ledge` can reach among `targets`, room pixels
## in the ledge's room. Returns {"ledges": [Ledge], "touches": [Touch],
## "pickups": [index]}, all of it reachable from the ledge by one platform.
func expand(ledge: ReachGraph.Ledge, targets: Array) -> Dictionary:
	var out := {"ledges": [], "touches": [], "pickups": []}
	if targets.is_empty() or ledge.moving:
		return out
	var info := _graph.room_info(ledge.room_id)
	var geo := _graph.geometry_of(info)
	var width := _graph.abilities.imprint_width
	var limit := _land_limit()
	if limit <= 0:
		return out
	var cell := float(Grid.CELL)
	var started := Time.get_ticks_usec()
	var arcs := _arcs_of(ledge, info, geo)
	stats["arcs"] += Time.get_ticks_usec() - started
	var candidates := {}
	for arc: Arc in arcs:
		if arc.path.size() < 3:
			continue
		var start_body := Rect2(arc.start - MovementSim.HALF, MovementSim.HALF * 2.0)
		for i in range(1, mini(arc.path.size(), limit + 1)):
			var before := arc.path[i - 1].y + MovementSim.HALF.y
			var after := arc.path[i].y + MovementSim.HALF.y
			if after <= before:
				continue
			var row := int(floor(before / cell)) + 1
			while float(row) * cell <= after:
				_collect(candidates, info, arc, row, arc.path[i].x, width, start_body, targets)
				row += 1
	var found := 0
	var landed: Array[Candidate] = []
	started = Time.get_ticks_usec()
	for key in candidates:
		if found >= MAX_CANDIDATES:
			break
		found += 1
		var candidate: Candidate = candidates[key]
		if _lands_on(info, geo, ledge, candidate, limit):
			landed.append(candidate)
	stats["lands"] += Time.get_ticks_usec() - started
	stats["candidates"] += found
	for candidate in landed:
		var leg := _leg_of(info, geo, candidate.last, 1, _graph.frame_limit)
		for index in leg.to_ledges:
			var target: ReachGraph.Ledge = _graph.ledges_in(ledge.room_id)[index]
			if not out["ledges"].has(target):
				out["ledges"].append(target)
		for touch in leg.touches:
			out["touches"].append(touch)
		for index in leg.pickups:
			if not out["pickups"].has(index):
				out["pickups"].append(index)
	return out


## How many ticks the jump onto a platform may run: the platform's life, less
## SPARE_TICKS to stand on it and push off. Zero means it is gone first.
func _land_limit() -> int:
	var life := int(_graph.abilities.imprint_duration * 60.0)
	return clampi(life - SPARE_TICKS, 0, _graph.frame_limit)


## Adds the platforms of `width` cells whose top is on `row` and that a body at
## `x` falling through that row would land on, if they are allowed and near
## enough to something out of reach to be worth trying.
func _collect(candidates: Dictionary, info: RoomInfo, arc: Arc, row: int, x: float, width: int, start_body: Rect2, targets: Array) -> void:
	var cell := float(Grid.CELL)
	var half := MovementSim.HALF.x
	var first := int(floor((x - half) / cell)) - width
	var last := int(floor((x + half) / cell)) + 1
	for column in range(first, last + 1):
		var left := float(column) * cell
		var right := left + float(width) * cell
		if right <= x - half + 0.5 or left >= x + half - 0.5:
			continue
		var key := "%d,%d" % [column, row]
		if candidates.has(key):
			var existing: Candidate = candidates[key]
			if existing.arcs.size() < MAX_ARCS_PER_CANDIDATE:
				existing.arcs.append(arc)
			continue
		var at := Vector2i(column, row)
		if not ImprintRules.check(info, at, width, start_body).is_empty():
			continue
		var rect := Grid.cell_rect(Rect2i(at, Vector2i(width, 1)))
		if not _near_a_target(rect, targets):
			continue
		var made := Candidate.new()
		made.cell = at
		made.arcs.append(arc)
		candidates[key] = made


## Whether any target is within a jump of standing on `platform`.
func _near_a_target(platform: Rect2, targets: Array) -> bool:
	var window := Rect2(platform.position.x - ReachGraph.REACH_X, platform.position.y - ReachGraph.REACH_UP, platform.size.x + ReachGraph.REACH_X * 2.0, ReachGraph.REACH_UP + ReachGraph.REACH_DOWN)
	for target: Rect2 in targets:
		if window.intersects(target):
			return true
	return false


## The cells of the blocks that may stay longest on a platform of `width`
## at `cell`, placed by a player whose centre is at `player_x`: the last of
## `ImprintPlatform.removal_order` for either facing. One cell, or two on a tie.
func _last_cells(cell: Vector2i, width: int, player_x: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var left := float(cell.x * Grid.CELL)
	for facing in [1, -1]:
		var order := ImprintPlatform.removal_order(width, left, player_x, facing)
		var last := Vector2i(cell.x + order[order.size() - 1], cell.y)
		if not out.has(last):
			out.append(last)
	return out


## Whether one of the jumps that made `candidate` a candidate still lands on
## the platform's last block once the platform is there to land on, with the
## last block worked out from where the jump starts. The jump is then run again
## with only the last block there, and has to land in the same place: an arc
## that touches another block differs between the two, and is dropped, because
## that block may be gone by then. Sets `candidate.last` to the block it landed on.
func _lands_on(info: RoomInfo, geo: ReachGraph.Geometry, ledge: ReachGraph.Ledge, candidate: Candidate, limit: int) -> bool:
	var width := _graph.abilities.imprint_width
	var platform := Grid.cell_rect(Rect2i(candidate.cell, Vector2i(width, 1)))
	var near := _graph.near_solids(geo.rects, ledge)
	var rects := near.duplicate()
	rects.append(platform)
	for arc: Arc in candidate.arcs:
		for last_cell in _last_cells(candidate.cell, width, arc.start.x):
			var last := Grid.cell_rect(Rect2i(last_cell, Vector2i(1, 1)))
			var at := _landing(geo, arc, rects, last, limit)
			if at.x != at.x:
				continue
			if width > 1:
				var alone := near.duplicate()
				alone.append(last)
				var again := _landing(geo, arc, alone, last, limit)
				if again.x != again.x or at.distance_to(again) >= 0.5:
					continue
			candidate.last = last_cell
			return true
	return false


## Where `arc`, run among `rects`, comes down on `last`, or NaN if it does not.
func _landing(geo: ReachGraph.Geometry, arc: Arc, rects: Array[Rect2], last: Rect2, limit: int) -> Vector2:
	var result := MovementSim.simulate_jump(_graph.movement(), rects, arc.start, Vector2(arc.speed, 0.0), arc.input, arc.hold, true, arc.jump, geo.triggers, geo.bounds, geo.hazards, [], NAN, 0, limit)
	if result["hazard"] or int(result["trigger"]) >= 0 or not result["landed"]:
		return Vector2(NAN, NAN)
	var at: Vector2 = result["position"]
	if absf(at.y + MovementSim.HALF.y - last.position.y) < 0.6 and at.x + MovementSim.HALF.x > last.position.x + 0.5 and at.x - MovementSim.HALF.x < last.end.x - 0.5:
		return at
	return Vector2(NAN, NAN)


func _leg_key(cell: Vector2i, width: int, limit: int) -> String:
	return "%d|%d|%d|%d" % [cell.x, cell.y, width, limit]


## Where a body standing on the platform can get to, worked out like a ledge.
## The platform is treated as a ledge of its own whose floor is the platform.
## A leg is kept for the rest of the run, and in the solver's cache, if it has
## one, for the next.
func _leg_of(info: RoomInfo, geo: ReachGraph.Geometry, cell: Vector2i, width: int, limit: int) -> ReachGraph.Ledge:
	var local := _leg_key(cell, width, limit)
	var key := "%s|%s" % [info.id, local]
	if _legs.has(key):
		return _legs[key]
	var started := Time.get_ticks_usec()
	var entry: SolverCache.Entry = _graph.cache.entry_for(info) if _graph.cache != null else null
	var stored = entry.legs.get(local) if entry != null else null
	var pseudo: ReachGraph.Ledge
	if stored != null:
		pseudo = ReachGraph.Ledge.new()
		pseudo.room_id = info.id
		pseudo.index = -1
		SolverCache.unpack(pseudo, stored)
		_graph.cache.stats["legs_cached"] += 1
	else:
		pseudo = _compute_leg(info, geo, cell, width, limit)
		stats["legs_made"] += 1
		if entry != null:
			entry.store_leg(local, pseudo)
			_graph.cache.stats["legs_solved"] += 1
	_legs[key] = pseudo
	stats["legs"] += Time.get_ticks_usec() - started
	return pseudo


func _compute_leg(info: RoomInfo, geo: ReachGraph.Geometry, cell: Vector2i, width: int, limit: int) -> ReachGraph.Ledge:
	var cellpx := float(Grid.CELL)
	var platform := Grid.cell_rect(Rect2i(cell, Vector2i(width, 1)))
	var pseudo := ReachGraph.Ledge.new()
	pseudo.room_id = info.id
	pseudo.index = -1
	pseudo.row = cell.y - 1
	pseudo.x0 = cell.x
	pseudo.x1 = cell.x + width - 1
	pseudo.top = platform.position.y
	pseudo.lo = platform.position.x - cellpx * 0.5 + 0.01
	pseudo.hi = platform.end.x + cellpx * 0.5 - 0.01
	var near := _graph.near_solids(geo.rects, pseudo)
	near.append(platform)
	for x in _graph.start_xs(pseudo):
		for input in [-1.0, 0.0, 1.0]:
			var speed := _graph.run_speed(pseudo, x, input)
			for hold in ReachGraph.HOLDS:
				_graph.try_plan(info, geo, pseudo, near, x, speed, input, hold, true, limit)
	_graph.walk_off(info, geo, pseudo, near, limit)
	return pseudo


## The jumps worth looking at from a ledge, with where each one goes.
func _arcs_of(ledge: ReachGraph.Ledge, info: RoomInfo, geo: ReachGraph.Geometry) -> Array:
	var key := "%s#%d" % [ledge.room_id, ledge.index]
	if _arcs.has(key):
		return _arcs[key]
	var out: Array[Arc] = []
	var near := _graph.near_solids(geo.rects, ledge)
	var cell := float(Grid.CELL)
	for x in _graph.start_xs(ledge):
		for input in [-1.0, 0.0, 1.0]:
			var speed := _graph.run_speed(ledge, x, input)
			for hold in ReachGraph.HOLDS:
				out.append(_arc(near, geo, ledge, x, speed, input, hold, true))
	for side in [-1.0, 1.0]:
		var past := float(ledge.x1 + 1) if side > 0.0 else float(ledge.x0 - 1)
		if info.is_solid(int(past), ledge.row) or info.is_hazard(int(past), ledge.row):
			continue
		var edge := float(ledge.x1 + 1) * cell - 1.0 if side > 0.0 else float(ledge.x0) * cell + 1.0
		out.append(_arc(near, geo, ledge, edge, side * _graph.movement().run_speed, side, 0, false))
		out.append(_arc(near, geo, ledge, edge, side * _graph.movement().run_speed, 0.0, 0, false))
	_arcs[key] = out
	return out


func _arc(near: Array[Rect2], geo: ReachGraph.Geometry, ledge: ReachGraph.Ledge, x: float, speed: float, input: float, hold: int, jump: bool) -> Arc:
	var arc := Arc.new()
	arc.start = Vector2(x, ledge.top - float(Grid.CELL) * 0.5)
	arc.speed = speed
	arc.input = input
	arc.hold = hold
	arc.jump = jump
	var result := MovementSim.simulate_jump(_graph.movement(), near, arc.start, Vector2(speed, 0.0), input, hold, true, jump, geo.triggers, geo.bounds, geo.hazards, [], NAN, 0, 180, true)
	arc.path = result["path"]
	return arc


## A jump from a ledge: how it was made and the position of the body each tick.
class Arc extends RefCounted:
	var start := Vector2.ZERO
	var speed := 0.0
	var input := 0.0
	var hold := 0
	var jump := true
	var path := PackedVector2Array()


## A platform that is worth trying, and the jumps that came down on it.
class Candidate extends RefCounted:
	var cell := Vector2i.ZERO
	## The block a jump was found to land on, which lasts: set by `_lands_on`.
	var last := Vector2i.ZERO
	var arcs: Array[Arc] = []
