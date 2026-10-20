class_name ReachGraph
extends RefCounted

## Where a player can get to, worked out with the same MovementSim the player
## runs. A ledge is a run of cells with air above and floor below. Edges are
## the jumps, drops and walks that move the player from one ledge to another
## ledge or into a door. Touching a door puts the body where Door.crossing
## puts it, with the velocity it had, and what that body lands on is where the
## door leads.
##
## The search tries a fixed set of input plans, so "reachable" means a
## concrete jump exists. "Unreachable" can still be a plan it did not try, so
## unreachable ledges are warnings, and a door or room nobody can reach is an
## error.

## How long the jump button is held, in physics ticks: a tap, a hop, a leap.
const HOLDS: Array[int] = [3, 8, 90]
## Ground needed to get up to run speed before a running jump, in pixels.
const RUN_UP := 5.0
## How far a path can wander from its start, in pixels, bounding which solids
## the simulation has to look at.
const REACH_X := 170.0
const REACH_UP := 100.0
const REACH_DOWN := 400.0
## How many ticks a body that comes through a door may fall before it is given
## up on. A room four screens tall is about 150 ticks of falling.
const FALL_LIMIT := 300
## How many doors a body can fall through in a row before it lands.
const MAX_CHAIN := 3
## Past this many lines of one kind, the report counts the rest.
const MAX_LINES := 6
## The most times `solve` collects pickups and solves again.
const MAX_ROUNDS := 8
## What a 3TM costs, in tokens.
const MACHINE_COST := TokenMachine.COST

var abilities: Abilities
## How many ticks a simulated path may run. The Imprint search shortens it so a
## platform placed for a jump is still there at the end of it.
var frame_limit := 180
var _cfg: MovementConfig
var _rooms: Dictionary
var _ledges := {}
var _geometry := {}
var _solved := {}
var _landings := {}
var _imprint: ImprintSearch
## Every pickup, token and 3TM in the world by id.
var _things := {}


## `ability_set` is what the player has, the starting abilities if left out.
## It is not consulted yet. Imprint will add platforms to the solids and widen
## what a path may do according to it.
func _init(rooms: Dictionary, movement: MovementConfig, ability_set: Abilities = null) -> void:
	_rooms = rooms
	_cfg = movement
	abilities = ability_set if ability_set != null else Abilities.new()
	for id in rooms:
		_ledges[id] = _find_ledges(rooms[id])
		for def in _things_of(rooms[id]):
			_things[def.id] = def


func movement() -> MovementConfig:
	return _cfg


func room_info(room_id: String) -> RoomInfo:
	return _rooms[room_id]


func ledges_in(room_id: String) -> Array[Ledge]:
	var out: Array[Ledge] = []
	out.assign(_ledges.get(room_id, []))
	return out


## Walks the whole graph from the start room's spawn with the abilities the
## graph was given.
func analyze(start_room: String) -> Report:
	var report := _analyze(start_room)
	_append_capped(report.errors, report.trap_lines)
	return report


## What the player can reach as they collect pickups. It solves with the
## starting abilities, takes every pickup, token and 3TM that solve could
## reach, and solves again with what they gave, until nothing new turns up.
## Tokens do nothing alone: a 3TM that was reached gives its upgrade if there
## are three tokens for it, and the machines are paid in order of their ids. A room's "needs" is
## the smallest set of pickups, found by dropping them one at a time, that it
## still opens with. Errors come from the last solve, except that a trap is
## judged where the player could first be in it, with the fewest abilities.
func solve(start_room: String) -> Report:
	var base := abilities
	var taken := {}
	var seen := {}
	var room_round := {}
	var ledge_round := {}
	var trap_lines: Array[String] = []
	var report := Report.new()
	for round in MAX_ROUNDS:
		abilities = _with(base, taken.keys())
		report = _analyze(start_room)
		for ledge in report.reached:
			if not room_round.has(ledge.room_id):
				room_round[ledge.room_id] = round
			if not ledge_round.has(ledge):
				ledge_round[ledge] = round
		for ledge in report.traps:
			if not seen.has(ledge):
				trap_lines.append("%s is a trap: once there, no path leads back to the start" % ledge.describe())
		for ledge in report.reached:
			seen[ledge] = true
		var fresh := 0
		for pickup in report.pickups:
			if pickup["reached"] and not taken.has(pickup["id"]):
				taken[pickup["id"]] = round
				fresh += 1
		if fresh == 0 or _with(base, taken.keys()).to_dict() == abilities.to_dict():
			break
	report.trap_lines = trap_lines
	_append_capped(report.errors, report.trap_lines)
	# What each thing needs: the pickups taken in earlier rounds, cut down to
	# the ones it still opens with.
	for room_id in room_round:
		report.needs[String(room_id)] = _needs(start_room, base, taken, int(room_round[room_id]), func(r: Report) -> bool: return r.reached_rooms.has(room_id))
	for ledge in ledge_round:
		if int(ledge_round[ledge]) > int(room_round[ledge.room_id]):
			report.needs["ledge|" + ledge.describe()] = _needs(start_room, base, taken, int(ledge_round[ledge]), func(r: Report) -> bool: return r.reached.has(ledge))
	for pickup in report.pickups:
		if pickup["reached"] and int(taken[pickup["id"]]) > 0:
			var id: String = pickup["id"]
			report.needs["pickup|" + id] = _needs(start_room, base, taken, int(taken[id]), func(r: Report) -> bool:
				for entry in r.pickups:
					if entry["id"] == id and entry["reached"]:
						return true
				return false
			)
	abilities = base
	return report


## The smallest set of the pickups taken before `round` that `opens` still
## holds with, found by dropping them one at a time.
func _needs(start_room: String, base: Abilities, taken: Dictionary, round: int, opens: Callable) -> Array:
	var needed: Array = []
	for id in taken:
		if int(taken[id]) < round:
			needed.append(id)
	for id in needed.duplicate():
		var without := needed.duplicate()
		without.erase(id)
		abilities = _with(base, without)
		if opens.call(_analyze(start_room)):
			needed = without
	needed.sort()
	return needed


## `base` with what the things named in `ids` give: a pickup's upgrade, and
## the upgrade of each 3TM that the tokens among them can pay for.
func _with(base: Abilities, ids: Array) -> Abilities:
	var out := base.copy()
	var tokens := 0
	var machines: Array[String] = []
	for id in ids:
		var def: EntityDef = _things.get(id)
		if def == null:
			continue
		match def.type:
			"pickup":
				out.apply(Upgrades.get_def(String(def.props["upgrade"])), Upgrades.parse_value(String(def.props["upgrade"]), String(def.props.get("value", ""))))
			"token":
				tokens += 1
			"machine":
				machines.append(String(id))
	machines.sort()
	for id in machines:
		if tokens < MACHINE_COST:
			break
		tokens -= MACHINE_COST
		var def: EntityDef = _things[id]
		out.apply(Upgrades.get_def(String(def.props["upgrade"])), Upgrades.parse_value(String(def.props["upgrade"]), String(def.props.get("value", ""))))
	return out


func _analyze(start_room: String) -> Report:
	var report := Report.new()
	if not _rooms.has(start_room):
		report.errors.append("There is no start room %s to search from" % start_room)
		return report
	var start_info: RoomInfo = _rooms[start_room]
	var start := _ledge_at_cell(start_info, start_info.spawn_cell)
	if start == null:
		report.errors.append("Room %s: the start %s at %s is not standing on anything" % [start_room, Tiles.SPAWN, start_info.spawn_cell])
		return report

	var run := Run.new()
	for id in _rooms:
		if not ExitRules.met(_rooms[id], {}):
			run.locked[id] = true
	run.queue.append(start)
	run.reached[start] = true
	_settle(run)
	var reached := run.reached
	var reached_doors := run.reached_doors
	var door_landings := run.door_landings
	var forward := run.forward

	# Walking the same edges backwards from the start finds every ledge that
	# can still get home. A reached ledge that cannot is a trap, unless an
	# Imprint platform put down from it gets it home.
	var home := _home(run, start)
	if abilities.imprint_unlocked:
		home = _place_imprints_to_get_home(run, start, home)
		# A platform put down on the way home may have reached what a locked room waits for.
		while _open_locks(run):
			_settle(run)
			home = _place_imprints_to_get_home(run, start, _home(run, start))
	var reached_rooms := {}
	for ledge in reached:
		reached_rooms[ledge.room_id] = true
	report.reached = reached
	report.reached_rooms = reached_rooms
	var unreached_rooms: Array[String] = []
	for id in _rooms:
		if not reached_rooms.has(id):
			unreached_rooms.append(String(id))
	unreached_rooms.sort()
	for id in unreached_rooms:
		report.errors.append("Room %s cannot be reached from room %s" % [id, start_room])

	var lost_doors: Array[String] = []
	var empty_doors: Array[String] = []
	var unreached_ledges: Array[String] = []
	var one_way_lines: Array[String] = []
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		for i in info.exits.size():
			var key := "%s#%d" % [id, i]
			var door := info.exits[i]
			if reached_rooms.has(id) and not reached_doors.has(key):
				if info.traps_allowed:
					# A one-way room is entered by the door the player fell through, so nobody inside can touch it.
					one_way_lines.append("Room %s: the %s door at %s cannot be reached from inside (trap: allowed)" % [id, door.edge, door.rect])
				else:
					lost_doors.append("Room %s: the %s door at %s cannot be reached" % [id, door.edge, door.rect])
					report.unreached_doors.append([String(id), door])
			elif reached_doors.has(key) and int(door_landings.get(key, 0)) == 0:
				empty_doors.append("Room %s: the %s door at %s leads into room %s, but a body going through it never lands on anything (a void, or only spikes)" % [id, door.edge, door.rect, door.dest_id])
		for ledge: Ledge in _ledges[id]:
			if not reached.has(ledge):
				report.unreached.append(ledge)
				if reached_rooms.has(id):
					unreached_ledges.append("%s cannot be reached" % ledge.describe())
			elif not home.has(ledge):
				if info.traps_allowed:
					report.one_way.append(ledge)
					one_way_lines.append("%s is one-way (trap: allowed): once there, no path leads back to the start" % ledge.describe())
				else:
					report.traps.append(ledge)
					report.trap_lines.append("%s is a trap: once there, no path leads back to the start" % ledge.describe())
	var lost_pickups: Array[String] = []
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		var defs := _things_of(info)
		for i in defs.size():
			var got := _pickup_reached(run, id, i)
			report.pickups.append({"id": defs[i].id, "type": defs[i].type, "room": String(id), "upgrade": String(defs[i].props.get("upgrade", "")), "value": String(defs[i].props.get("value", "")), "reached": got})
			if reached_rooms.has(id) and not got:
				lost_pickups.append("Room %s: %s %s at cell %s cannot be reached: no jump from a ledge the player gets to touches it" % [id, defs[i].type, defs[i].id, defs[i].cell])
	_append_capped(report.errors, lost_pickups)
	_append_capped(report.errors, lost_doors)
	_append_capped(report.errors, empty_doors)
	_append_capped(report.warnings, unreached_ledges)
	_append_capped(report.warnings, one_way_lines)
	report.reached_ledges = reached.size()
	report.total_ledges = 0
	for id in _ledges:
		report.total_ledges += _ledges[id].size()
	return report


## Spreads out from the ledges in the queue, following jumps, drops, walks and
## the doors the player touches, until nothing new is reached. Imprint
## platforms found by `_place_imprints` are extra edges, kept in `run`.
func _flood(run: Run) -> void:
	while not run.queue.is_empty():
		var ledge: Ledge = run.queue.pop_back()
		var info: RoomInfo = _rooms[ledge.room_id]
		_ensure_edges(info)
		var next: Array[Ledge] = []
		for index in ledge.to_ledges:
			next.append(_ledges[ledge.room_id][index])
		next.append_array(run.extra_to.get(ledge, []))
		var touches: Array[Touch] = []
		touches.append_array(ledge.touches)
		touches.append_array(run.extra_touches.get(ledge, []))
		# The doors of a locked room are blocks: its touches wait until it opens.
		if run.locked.has(ledge.room_id) and not touches.is_empty():
			if not run.held.has(ledge.room_id):
				run.held[ledge.room_id] = []
			if not run.held[ledge.room_id].has(ledge):
				run.held[ledge.room_id].append(ledge)
			touches.clear()
		for touch in touches:
			var key := "%s#%d" % [ledge.room_id, touch.door]
			run.reached_doors[key] = true
			var landings := _landings_of(info, touch, 0)
			run.door_landings[key] = int(run.door_landings.get(key, 0)) + landings.size()
			next.append_array(landings)
		run.forward[ledge] = next
		for target in next:
			if not run.reached.has(target):
				run.reached[target] = true
				run.queue.append(target)


## Floods, then (with Imprint) searches for platforms, and opens any room whose
## exit rule has become met, until nothing more changes.
func _settle(run: Run) -> void:
	while true:
		_flood(run)
		if abilities.imprint_unlocked:
			_place_imprints(run)
		if not _open_locks(run):
			return


## Opens every locked room whose rule is now met by what this run has reached,
## and queues the ledges whose door touches were waiting. Says whether any opened.
func _open_locks(run: Run) -> bool:
	var opened := false
	for id in run.locked.keys():
		var flags := {}
		for i in _things_of(_rooms[id]).size():
			if _pickup_reached(run, id, i):
				flags[Entities.flag_for(_things_of(_rooms[id])[i])] = true
		if not ExitRules.met(_rooms[id], flags):
			continue
		run.locked.erase(id)
		opened = true
		for ledge in run.held.get(id, []):
			run.queue.append(ledge)
		run.held.erase(id)
	return opened


## With Imprint, a platform put down from a ledge can bring more places within
## a jump. Every reached ledge is searched once for platforms that help reach
## something still out of reach, and the new places are flooded, until nothing
## more opens up.
func _place_imprints(run: Run) -> void:
	if _imprint == null:
		_imprint = ImprintSearch.new(self)
	while true:
		var targets := _unreached_targets(run)
		if targets.is_empty():
			return
		var opened := false
		for ledge in run.reached.keys():
			if run.expanded.has(ledge):
				continue
			run.expanded[ledge] = true
			var found := _imprint.expand(ledge, targets.get(ledge.room_id, []))
			if found["ledges"].is_empty() and found["touches"].is_empty() and found["pickups"].is_empty():
				continue
			opened = true
			if not run.extra_to.has(ledge):
				run.extra_to[ledge] = []
				run.extra_touches[ledge] = []
				run.extra_pickups[ledge] = []
			run.extra_to[ledge].append_array(found["ledges"])
			run.extra_touches[ledge].append_array(found["touches"])
			run.extra_pickups[ledge].append_array(found["pickups"])
			run.queue.append(ledge)
		_flood(run)
		if not opened and not _has_unexpanded(run):
			return


## The ledges from which the start can still be reached.
func _home(run: Run, start: Ledge) -> Dictionary:
	var back := {}
	for ledge in run.forward:
		for target in run.forward[ledge]:
			if not back.has(target):
				back[target] = []
			back[target].append(ledge)
	var home := {start: true}
	var home_queue: Array[Ledge] = [start]
	while not home_queue.is_empty():
		var ledge: Ledge = home_queue.pop_back()
		for source in back.get(ledge, []):
			if not home.has(source):
				home[source] = true
				home_queue.append(source)
	return home


## A ledge with no way home may have one with a platform. Each such ledge is
## searched once, for platforms that bring it within a jump of a ledge that is
## home or of a door.
func _place_imprints_to_get_home(run: Run, start: Ledge, home: Dictionary) -> Dictionary:
	if _imprint == null:
		_imprint = ImprintSearch.new(self)
	var tried := {}
	while true:
		var opened := false
		for ledge in run.reached.keys():
			if home.has(ledge) or tried.has(ledge):
				continue
			tried[ledge] = true
			var targets: Array[Rect2] = []
			for other: Ledge in _ledges[ledge.room_id]:
				if home.has(other):
					targets.append(Rect2(other.lo - 5.0, other.top - 10.0, other.hi - other.lo + 10.0, 10.0))
			for door in _rooms[ledge.room_id].exits:
				targets.append(door.trigger_rect())
			var found := _imprint.expand(ledge, targets)
			if found["ledges"].is_empty() and found["touches"].is_empty():
				continue
			opened = true
			if not run.extra_to.has(ledge):
				run.extra_to[ledge] = []
				run.extra_touches[ledge] = []
				run.extra_pickups[ledge] = []
			run.extra_to[ledge].append_array(found["ledges"])
			run.extra_touches[ledge].append_array(found["touches"])
			run.extra_pickups[ledge].append_array(found["pickups"])
			run.queue.append(ledge)
		if not opened:
			return home
		_flood(run)
		home = _home(run, start)
	return home


func _has_unexpanded(run: Run) -> bool:
	for ledge in run.reached:
		if not run.expanded.has(ledge):
			return true
	return false


## Places nobody has reached yet, as room pixels per room: ledges to stand on,
## door triggers, pickups.
func _unreached_targets(run: Run) -> Dictionary:
	var out := {}
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		var list: Array[Rect2] = []
		for ledge: Ledge in _ledges[id]:
			if not run.reached.has(ledge):
				list.append(Rect2(ledge.lo - 5.0, ledge.top - 10.0, ledge.hi - ledge.lo + 10.0, 10.0))
		for i in info.exits.size():
			if not run.reached_doors.has("%s#%d" % [id, i]):
				list.append(info.exits[i].trigger_rect())
		var geo := geometry_of(info)
		for i in geo.things.size():
			if not _pickup_reached(run, id, i):
				list.append(geo.things[i])
		if not list.is_empty():
			out[id] = list
	return out


func _pickup_reached(run: Run, room_id: String, index: int) -> bool:
	for ledge: Ledge in _ledges[room_id]:
		if not run.reached.has(ledge):
			continue
		if ledge.pickups.has(index) or run.extra_pickups.get(ledge, []).has(index):
			return true
	return false


func _append_capped(into: Array[String], lines: Array[String]) -> void:
	lines.sort()
	for i in mini(lines.size(), MAX_LINES):
		into.append(lines[i])
	if lines.size() > MAX_LINES:
		into.append("... and %d more like that" % (lines.size() - MAX_LINES))


# --- ledges ---------------------------------------------------------------


func _find_ledges(info: RoomInfo) -> Array[Ledge]:
	var out: Array[Ledge] = []
	var width := info.cell_size.x
	for y in info.rows.size():
		var x := 0
		while x < width:
			if not _standable(info, x, y):
				x += 1
				continue
			var ledge := Ledge.new()
			ledge.room_id = info.id
			ledge.index = out.size()
			ledge.row = y
			ledge.x0 = x
			while x < width and _standable(info, x, y):
				x += 1
			ledge.x1 = x - 1
			var cell := float(Grid.CELL)
			ledge.top = float(y + 1) * cell
			# A body hangs on a ledge until its centre is half a cell past the
			# end, unless a wall or spikes stop it first.
			var wall_left := info.is_solid(ledge.x0 - 1, y) or info.is_hazard(ledge.x0 - 1, y)
			var wall_right := info.is_solid(ledge.x1 + 1, y) or info.is_hazard(ledge.x1 + 1, y)
			ledge.lo = float(ledge.x0) * cell + (cell * 0.5 if wall_left else -cell * 0.5 + 0.01)
			ledge.hi = float(ledge.x1 + 1) * cell + (-cell * 0.5 if wall_right else cell * 0.5 - 0.01)
			out.append(ledge)
	return out


## Air with a floor under it. The floor has to be in the room: below the
## bottom edge there is nothing for a body to stand on.
func _standable(info: RoomInfo, x: int, y: int) -> bool:
	return y + 1 < info.rows.size() and not info.is_solid(x, y) and not info.is_hazard(x, y) and info.is_solid(x, y + 1)


func _ledge_at_cell(info: RoomInfo, cell: Vector2i) -> Ledge:
	for ledge: Ledge in _ledges[info.id]:
		if ledge.row == cell.y and cell.x >= ledge.x0 and cell.x <= ledge.x1:
			return ledge
	return null


## The ledge a body resting at `pos` is standing on.
func ledge_at_position(info: RoomInfo, pos: Vector2) -> Ledge:
	var cell := float(Grid.CELL)
	var row := roundi((pos.y + cell * 0.5) / cell) - 1
	var centre := floori(pos.x / cell)
	var candidates: Array[int] = [centre, floori((pos.x - 4.99) / cell), floori((pos.x + 4.99) / cell)]
	for x in candidates:
		var ledge := _ledge_at_cell(info, Vector2i(x, row))
		if ledge != null:
			return ledge
	return null


# --- doors ----------------------------------------------------------------


## The ledges a body that touched a door ends up on.
func _landings_of(info: RoomInfo, touch: Touch, depth: int) -> Array[Ledge]:
	var key := "%s#%s" % [info.id, touch.key()]
	if _landings.has(key):
		return _landings[key]
	var unsolved: Array[Ledge] = []
	_landings[key] = unsolved  # a door that leads back here before it is solved lands nowhere
	var door := info.exits[touch.door]
	var dest: RoomInfo = _rooms[door.dest_id]
	var source_origin := Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	var dest_origin := Vector2(dest.grid_pos) * Grid.SCREEN_SIZE
	var crossed := Door.crossing(door, dest, source_origin + touch.position, touch.velocity)
	var far := dest.exits.find(dest.door_by_rect(door.dest_rect))
	var out := _land(dest, crossed["position"] - dest_origin, crossed["velocity"], far, depth)
	_landings[key] = out
	return out


## What a body put at `pos` in `dest`, moving at `vel`, comes to rest on. It
## may steer left or right or not at all while it falls. `skip_door` is the
## door it just came through.
func _land(dest: RoomInfo, pos: Vector2, vel: Vector2, skip_door: int, depth: int) -> Array[Ledge]:
	var out: Array[Ledge] = []
	var geo := geometry_of(dest)
	var standing := MovementSim.standing(pos, geo.rects)
	if standing and vel.y >= 0.0:
		var ledge := ledge_at_position(dest, pos)
		if ledge != null:
			out.append(ledge)
		return out
	var near := _near_fall(geo, pos)
	var triggers := geo.triggers.duplicate()
	if skip_door >= 0:
		triggers[skip_door] = Rect2(-1.0e6, -1.0e6, 0.0, 0.0)
	for input in [-1.0, 0.0, 1.0]:
		var result := MovementSim.simulate_jump(_cfg, near, pos, vel, input, 0, standing, false, triggers, geo.bounds, geo.hazards, [], NAN, 0, FALL_LIMIT)
		if result["hazard"]:
			continue
		var door := int(result["trigger"])
		var ledge: Ledge = null
		if door >= 0:
			if depth < MAX_CHAIN:
				var chained := Touch.new(door, result["position"], result["velocity"])
				for landed in _landings_of(dest, chained, depth + 1):
					if not out.has(landed):
						out.append(landed)
		elif result["landed"]:
			ledge = ledge_at_position(dest, result["position"])
		if ledge != null and not out.has(ledge):
			out.append(ledge)
	return out


# --- edges ----------------------------------------------------------------


func geometry_of(info: RoomInfo) -> Geometry:
	if not _geometry.has(info.id):
		var geo := Geometry.new()
		for cell_rect in info.solids:
			geo.rects.append(Grid.cell_rect(cell_rect))
		for door in info.exits:
			geo.triggers.append(door.trigger_rect())
		for cell in info.hazards:
			geo.hazards.append(Grid.cell_rect(Rect2i(cell, Vector2i.ONE)))
		for def in _things_of(info):
			if def.type == "machine":
				geo.things.append(TokenMachine.touch_rect_for(def.cell))
			else:
				var centre := Grid.cell_center(def.cell)
				geo.things.append(Rect2(centre - Vector2(Pickup.HALF, Pickup.HALF), Vector2(Pickup.HALF, Pickup.HALF) * 2.0))
		geo.bounds = Rect2(Vector2(-40.0, -120.0), info.pixel_size + Vector2(80.0, 160.0))
		_geometry[info.id] = geo
	return _geometry[info.id]


func _ensure_edges(info: RoomInfo) -> void:
	if _solved.has(info.id):
		return
	_solved[info.id] = true
	var geo := geometry_of(info)
	for ledge: Ledge in _ledges[info.id]:
		_walk_to_doors(ledge, geo.triggers)
		_stand_at_things(ledge, geo.things)
		var near := near_solids(geo.rects, ledge)
		for x in start_xs(ledge):
			for input in [-1.0, 0.0, 1.0]:
				var speed := run_speed(ledge, x, input)
				for hold in HOLDS:
					try_plan(info, geo, ledge, near, x, speed, input, hold, true)
		walk_off(info, geo, ledge, near)


## A ledge that runs into a door's trigger walks into it.
func _walk_to_doors(ledge: Ledge, triggers: Array[Rect2]) -> void:
	var half := float(Grid.CELL) * 0.5
	for i in triggers.size():
		var trigger := triggers[i]
		var overlaps_height := trigger.position.y < ledge.top and trigger.end.y > ledge.top - float(Grid.CELL)
		var overlaps_width := ledge.hi + half > trigger.position.x and ledge.lo - half < trigger.end.x
		if overlaps_height and overlaps_width:
			var spot := clampf(trigger.get_center().x, ledge.lo, ledge.hi)
			var heading := signf(trigger.get_center().x - spot)
			var running := _cfg.run_speed if ledge.hi - ledge.lo >= RUN_UP else 0.0
			ledge.add_touch(i, Vector2(spot, ledge.top - half), Vector2(heading * running, 0.0))


## A body standing on the ledge touches a pickup, token or 3TM its body overlaps.
func _stand_at_things(ledge: Ledge, things: Array[Rect2]) -> void:
	var cell := float(Grid.CELL)
	var standing := Rect2(ledge.lo - cell * 0.5, ledge.top - cell, ledge.hi - ledge.lo + cell, cell)
	for i in things.size():
		if standing.intersects(things[i]):
			ledge.add_pickup(i)


## The pickups, tokens and 3TMs in a room, in the order Geometry.things lists
## their rects. Touching one is what takes it or works it.
func _things_of(info: RoomInfo) -> Array[EntityDef]:
	var out: Array[EntityDef] = []
	for def in info.entities:
		if Entities.is_touchable(def):
			out.append(def)
	return out


## Solids close enough to matter, so each simulated frame has fewer to test.
func near_solids(rects: Array[Rect2], ledge: Ledge) -> Array[Rect2]:
	var span := Rect2(ledge.lo - REACH_X, ledge.top - REACH_UP, ledge.hi - ledge.lo + REACH_X * 2.0, REACH_UP + REACH_DOWN)
	return _within(rects, span)


## The solids a body falling from `pos` can meet: some way to either side and
## all the way down to the bottom of the room, however tall it is.
func _near_fall(geo: Geometry, pos: Vector2) -> Array[Rect2]:
	var top := pos.y - REACH_DOWN
	return _within(geo.rects, Rect2(pos.x - REACH_X, top, REACH_X * 2.0, geo.bounds.end.y - top))


func _within(rects: Array[Rect2], span: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		if rect.intersects(span):
			out.append(rect)
	return out


## Where to start a jump: the middle of every cell, and the two spots at the
## very ends, which a body can still stand on.
func start_xs(ledge: Ledge) -> Array[float]:
	var xs: Array[float] = [ledge.lo]
	for x in range(ledge.x0, ledge.x1 + 1):
		xs.append((float(x) + 0.5) * float(Grid.CELL))
	xs.append(ledge.hi)
	return xs


## Running speed at the start, which needs a few pixels of ground behind it.
func run_speed(ledge: Ledge, x: float, input: float) -> float:
	if input > 0.0 and x - ledge.lo >= RUN_UP:
		return _cfg.run_speed
	if input < 0.0 and ledge.hi - x >= RUN_UP:
		return -_cfg.run_speed
	return 0.0


func walk_off(info: RoomInfo, geo: Geometry, ledge: Ledge, near: Array[Rect2]) -> void:
	var cell := float(Grid.CELL)
	if not info.is_solid(ledge.x1 + 1, ledge.row) and not info.is_hazard(ledge.x1 + 1, ledge.row):
		var edge := float(ledge.x1 + 1) * cell - 1.0
		try_plan(info, geo, ledge, near, edge, _cfg.run_speed, 1.0, 0, false)
		try_plan(info, geo, ledge, near, edge, _cfg.run_speed, 0.0, 0, false)
	if not info.is_solid(ledge.x0 - 1, ledge.row) and not info.is_hazard(ledge.x0 - 1, ledge.row):
		var edge := float(ledge.x0) * cell + 1.0
		try_plan(info, geo, ledge, near, edge, -_cfg.run_speed, -1.0, 0, false)
		try_plan(info, geo, ledge, near, edge, -_cfg.run_speed, 0.0, 0, false)


func try_plan(info: RoomInfo, geo: Geometry, ledge: Ledge, near: Array[Rect2], x: float, speed: float, input: float, hold: int, jump: bool) -> void:
	var start := Vector2(x, ledge.top - float(Grid.CELL) * 0.5)
	var result := MovementSim.simulate_jump(_cfg, near, start, Vector2(speed, 0.0), input, hold, true, jump, geo.triggers, geo.bounds, geo.hazards, geo.things, NAN, 0, frame_limit)
	# A pickup is taken even on a path that then dies on spikes.
	for index in result["collected"]:
		ledge.add_pickup(index)
	if result["hazard"]:
		return
	var door := int(result["trigger"])
	if door >= 0:
		ledge.add_touch(door, result["position"], result["velocity"])
	elif result["landed"]:
		var target := ledge_at_position(info, result["position"])
		if target != null and target != ledge:
			ledge.add_ledge(target.index)


## The state of one solve: what has been reached and how.
class Run extends RefCounted:
	var queue: Array[Ledge] = []
	var reached := {}
	var reached_doors := {}
	var door_landings := {}
	var forward := {}
	var expanded := {}
	var extra_to := {}
	var extra_touches := {}
	var extra_pickups := {}
	## Rooms whose exit rule is not met yet, and for each the ledges whose door
	## touches are waiting for it.
	var locked := {}
	var held := {}


class Geometry extends RefCounted:
	var rects: Array[Rect2] = []
	var triggers: Array[Rect2] = []
	var hazards: Array[Rect2] = []
	## The rects that touch a pickup, token or 3TM.
	var things: Array[Rect2] = []
	var bounds := Rect2()


## A body touching a door: which door, and where and how fast, in room pixels.
class Touch extends RefCounted:
	var door := 0
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO

	func _init(door_index: int, at: Vector2, moving: Vector2) -> void:
		door = door_index
		position = at
		velocity = moving

	## Touches that differ by less than this are one touch.
	func key() -> String:
		return "%d|%d|%d|%d|%d" % [door, roundi(position.x / 10.0), roundi(position.y / 10.0), roundi(velocity.x / 45.0), roundi(velocity.y / 100.0)]


class Ledge extends RefCounted:
	var room_id := ""
	var index := 0
	var row := 0
	var x0 := 0
	var x1 := 0
	## Room-local y of the surface, in pixels.
	var top := 0.0
	## Room-local x range a body's centre can have while standing here.
	var lo := 0.0
	var hi := 0.0
	var to_ledges: Array[int] = []
	var touches: Array[Touch] = []
	## Indices of the room's pickups that some path from here touches.
	var pickups: Array[int] = []
	var _touch_keys := {}

	func add_ledge(target: int) -> void:
		if not to_ledges.has(target):
			to_ledges.append(target)

	func add_pickup(index: int) -> void:
		if not pickups.has(index):
			pickups.append(index)

	func add_touch(door: int, at: Vector2, moving: Vector2) -> void:
		var touch := Touch.new(door, at, moving)
		if not _touch_keys.has(touch.key()):
			_touch_keys[touch.key()] = true
			touches.append(touch)

	func describe() -> String:
		return "Room %s: the ledge on row %d, cells %d-%d" % [room_id, row, x0, x1]


class Report extends RefCounted:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var reached_ledges := 0
	var total_ledges := 0
	var unreached: Array[Ledge] = []
	var traps: Array[Ledge] = []
	## Ledges with no way home in a room that allows it (`trap: allowed`).
	var one_way: Array[Ledge] = []
	## [room_id, Door] pairs.
	var unreached_doors: Array = []
	## One entry per pickup: {id, room, upgrade, value, reached}.
	var pickups: Array[Dictionary] = []
	## Every ledge that was reached, and the ids of the rooms that were.
	var reached := {}
	var reached_rooms := {}
	var trap_lines: Array[String] = []
	## From `solve`: room id -> the pickup ids it needs first. Empty for a room
	## that opens with the starting abilities.
	var needs := {}
