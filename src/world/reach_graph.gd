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
## How many doors a body can fall through in a row before it lands.
const MAX_CHAIN := 3
## Past this many lines of one kind, the report counts the rest.
const MAX_LINES := 6

var abilities: Abilities
var _cfg: MovementConfig
var _rooms: Dictionary
var _ledges := {}
var _geometry := {}
var _solved := {}
var _landings := {}


## `ability_set` is what the player has, the starting abilities if left out.
## It is not consulted yet. Imprint will add platforms to the solids and widen
## what a path may do according to it.
func _init(rooms: Dictionary, movement: MovementConfig, ability_set: Abilities = null) -> void:
	_rooms = rooms
	_cfg = movement
	abilities = ability_set if ability_set != null else Abilities.new()
	for id in rooms:
		_ledges[id] = _find_ledges(rooms[id])


func ledges_in(room_id: String) -> Array[Ledge]:
	var out: Array[Ledge] = []
	out.assign(_ledges.get(room_id, []))
	return out


## Walks the whole graph from the start room's spawn.
func analyze(start_room: String) -> Report:
	var report := Report.new()
	if not _rooms.has(start_room):
		report.errors.append("There is no start room %s to search from" % start_room)
		return report
	var start_info: RoomInfo = _rooms[start_room]
	var start := _ledge_at_cell(start_info, start_info.spawn_cell)
	if start == null:
		report.errors.append("Room %s: the start %s at %s is not standing on anything" % [start_room, Tiles.SPAWN, start_info.spawn_cell])
		return report

	var reached := {}
	var reached_doors := {}
	# Where the bodies that touched each door ended up, to catch a door that
	# drops everyone into a void or onto spikes.
	var door_landings := {}
	var forward := {}
	var queue: Array[Ledge] = [start]
	reached[start] = true
	while not queue.is_empty():
		var ledge: Ledge = queue.pop_back()
		var info: RoomInfo = _rooms[ledge.room_id]
		_ensure_edges(info)
		var next: Array[Ledge] = []
		for index in ledge.to_ledges:
			next.append(_ledges[ledge.room_id][index])
		for touch in ledge.touches:
			var key := "%s#%d" % [ledge.room_id, touch.door]
			reached_doors[key] = true
			var landings := _landings_of(info, touch, 0)
			door_landings[key] = int(door_landings.get(key, 0)) + landings.size()
			next.append_array(landings)
		forward[ledge] = next
		for target in next:
			if not reached.has(target):
				reached[target] = true
				queue.append(target)

	# Walking the same edges backwards from the start finds every ledge that
	# can still get home. A reached ledge that cannot is a trap.
	var back := {}
	for ledge in forward:
		for target in forward[ledge]:
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

	var reached_rooms := {}
	for ledge in reached:
		reached_rooms[ledge.room_id] = true
	var unreached_rooms: Array[String] = []
	for id in _rooms:
		if not reached_rooms.has(id):
			unreached_rooms.append(String(id))
	unreached_rooms.sort()
	for id in unreached_rooms:
		report.errors.append("Room %s cannot be reached from room %s" % [id, start_room])

	var lost_doors: Array[String] = []
	var empty_doors: Array[String] = []
	var traps: Array[String] = []
	var unreached_ledges: Array[String] = []
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		for i in info.exits.size():
			var key := "%s#%d" % [id, i]
			var door := info.exits[i]
			if reached_rooms.has(id) and not reached_doors.has(key):
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
				report.traps.append(ledge)
				traps.append("%s is a trap: once there, no path leads back to the start" % ledge.describe())
	var lost_pickups: Array[String] = []
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		var defs := _pickups_of(info)
		for i in defs.size():
			var got := false
			for ledge: Ledge in _ledges[id]:
				if reached.has(ledge) and ledge.pickups.has(i):
					got = true
					break
			report.pickups.append({"id": defs[i].id, "room": String(id), "upgrade": String(defs[i].props["upgrade"]), "value": String(defs[i].props.get("value", "")), "reached": got})
			if reached_rooms.has(id) and not got:
				lost_pickups.append("Room %s: pickup %s at cell %s cannot be reached: no jump from a ledge the player gets to touches it" % [id, defs[i].id, defs[i].cell])
	_append_capped(report.errors, lost_pickups)
	_append_capped(report.errors, lost_doors)
	_append_capped(report.errors, empty_doors)
	_append_capped(report.errors, traps)
	_append_capped(report.warnings, unreached_ledges)
	report.reached_ledges = reached.size()
	report.total_ledges = 0
	for id in _ledges:
		report.total_ledges += _ledges[id].size()
	return report


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
func _ledge_at_position(info: RoomInfo, pos: Vector2) -> Ledge:
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
	var geo := _geometry_of(dest)
	var standing := MovementSim.standing(pos, geo.rects)
	if standing and vel.y >= 0.0:
		var ledge := _ledge_at_position(dest, pos)
		if ledge != null:
			out.append(ledge)
		return out
	var near := _near_point(geo.rects, pos)
	var triggers := geo.triggers.duplicate()
	if skip_door >= 0:
		triggers[skip_door] = Rect2(-1.0e6, -1.0e6, 0.0, 0.0)
	for input in [-1.0, 0.0, 1.0]:
		var result := MovementSim.simulate_jump(_cfg, near, pos, vel, input, 0, standing, false, triggers, geo.bounds, geo.hazards)
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
			ledge = _ledge_at_position(dest, result["position"])
		if ledge != null and not out.has(ledge):
			out.append(ledge)
	return out


# --- edges ----------------------------------------------------------------


func _geometry_of(info: RoomInfo) -> Geometry:
	if not _geometry.has(info.id):
		var geo := Geometry.new()
		for cell_rect in info.solids:
			geo.rects.append(Grid.cell_rect(cell_rect))
		for door in info.exits:
			geo.triggers.append(door.trigger_rect())
		for cell in info.hazards:
			geo.hazards.append(Grid.cell_rect(Rect2i(cell, Vector2i.ONE)))
		for def in _pickups_of(info):
			var centre := Grid.cell_center(def.cell)
			geo.pickups.append(Rect2(centre - Vector2(Pickup.HALF, Pickup.HALF), Vector2(Pickup.HALF, Pickup.HALF) * 2.0))
		geo.bounds = Rect2(Vector2(-40.0, -120.0), info.pixel_size + Vector2(80.0, 160.0))
		_geometry[info.id] = geo
	return _geometry[info.id]


func _ensure_edges(info: RoomInfo) -> void:
	if _solved.has(info.id):
		return
	_solved[info.id] = true
	var geo := _geometry_of(info)
	for ledge: Ledge in _ledges[info.id]:
		_walk_to_doors(ledge, geo.triggers)
		_stand_at_pickups(ledge, geo.pickups)
		var near := _near(geo.rects, ledge)
		for x in _start_xs(ledge):
			for input in [-1.0, 0.0, 1.0]:
				var speed := _run_speed(ledge, x, input)
				for hold in HOLDS:
					_try(info, geo, ledge, near, x, speed, input, hold, true)
		_walk_off(info, geo, ledge, near)


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


## A body standing on the ledge collects a pickup its body overlaps.
func _stand_at_pickups(ledge: Ledge, pickups: Array[Rect2]) -> void:
	var cell := float(Grid.CELL)
	var standing := Rect2(ledge.lo - cell * 0.5, ledge.top - cell, ledge.hi - ledge.lo + cell, cell)
	for i in pickups.size():
		if standing.intersects(pickups[i]):
			ledge.add_pickup(i)


## The pickups in a room, in the order Geometry.pickups lists their rects.
func _pickups_of(info: RoomInfo) -> Array[EntityDef]:
	var out: Array[EntityDef] = []
	for def in info.entities:
		if def.type == "pickup":
			out.append(def)
	return out


## Solids close enough to matter, so each simulated frame has fewer to test.
func _near(rects: Array[Rect2], ledge: Ledge) -> Array[Rect2]:
	var span := Rect2(ledge.lo - REACH_X, ledge.top - REACH_UP, ledge.hi - ledge.lo + REACH_X * 2.0, REACH_UP + REACH_DOWN)
	return _within(rects, span)


func _near_point(rects: Array[Rect2], pos: Vector2) -> Array[Rect2]:
	return _within(rects, Rect2(pos.x - REACH_X, pos.y - REACH_DOWN, REACH_X * 2.0, REACH_DOWN + REACH_DOWN))


func _within(rects: Array[Rect2], span: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		if rect.intersects(span):
			out.append(rect)
	return out


## Where to start a jump: the middle of every cell, and the two spots at the
## very ends, which a body can still stand on.
func _start_xs(ledge: Ledge) -> Array[float]:
	var xs: Array[float] = [ledge.lo]
	for x in range(ledge.x0, ledge.x1 + 1):
		xs.append((float(x) + 0.5) * float(Grid.CELL))
	xs.append(ledge.hi)
	return xs


## Running speed at the start, which needs a few pixels of ground behind it.
func _run_speed(ledge: Ledge, x: float, input: float) -> float:
	if input > 0.0 and x - ledge.lo >= RUN_UP:
		return _cfg.run_speed
	if input < 0.0 and ledge.hi - x >= RUN_UP:
		return -_cfg.run_speed
	return 0.0


func _walk_off(info: RoomInfo, geo: Geometry, ledge: Ledge, near: Array[Rect2]) -> void:
	var cell := float(Grid.CELL)
	if not info.is_solid(ledge.x1 + 1, ledge.row) and not info.is_hazard(ledge.x1 + 1, ledge.row):
		var edge := float(ledge.x1 + 1) * cell - 1.0
		_try(info, geo, ledge, near, edge, _cfg.run_speed, 1.0, 0, false)
		_try(info, geo, ledge, near, edge, _cfg.run_speed, 0.0, 0, false)
	if not info.is_solid(ledge.x0 - 1, ledge.row) and not info.is_hazard(ledge.x0 - 1, ledge.row):
		var edge := float(ledge.x0) * cell + 1.0
		_try(info, geo, ledge, near, edge, -_cfg.run_speed, -1.0, 0, false)
		_try(info, geo, ledge, near, edge, -_cfg.run_speed, 0.0, 0, false)


func _try(info: RoomInfo, geo: Geometry, ledge: Ledge, near: Array[Rect2], x: float, speed: float, input: float, hold: int, jump: bool) -> void:
	var start := Vector2(x, ledge.top - float(Grid.CELL) * 0.5)
	var result := MovementSim.simulate_jump(_cfg, near, start, Vector2(speed, 0.0), input, hold, true, jump, geo.triggers, geo.bounds, geo.hazards, geo.pickups)
	# A pickup is taken even on a path that then dies on spikes.
	for index in result["collected"]:
		ledge.add_pickup(index)
	if result["hazard"]:
		return
	var door := int(result["trigger"])
	if door >= 0:
		ledge.add_touch(door, result["position"], result["velocity"])
	elif result["landed"]:
		var target := _ledge_at_position(info, result["position"])
		if target != null and target != ledge:
			ledge.add_ledge(target.index)


class Geometry extends RefCounted:
	var rects: Array[Rect2] = []
	var triggers: Array[Rect2] = []
	var hazards: Array[Rect2] = []
	var pickups: Array[Rect2] = []
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
	## [room_id, Door] pairs.
	var unreached_doors: Array = []
	## One entry per pickup: {id, room, upgrade, value, reached}.
	var pickups: Array[Dictionary] = []
