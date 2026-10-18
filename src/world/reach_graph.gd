class_name ReachGraph
extends RefCounted

## Where a player can get to, worked out with the same MovementSim the player
## runs. A ledge is a run of cells with air above and floor below. Edges are
## the jumps, drops and walks that move the player from one ledge to another
## ledge or to a door. A door leads to the ledge its far side puts you on.
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
## Past this many lines of one kind, the report counts the rest.
const MAX_LINES := 6

var abilities: Dictionary
var _cfg: MovementConfig
var _rooms: Dictionary
var _ledges := {}
var _solved := {}
var _arrivals := {}


## `ability_set` is not consulted yet. Imprint will add platforms to the
## solids and widen what a path may do.
func _init(rooms: Dictionary, movement: MovementConfig, ability_set: Dictionary = {}) -> void:
	_rooms = rooms
	_cfg = movement
	abilities = ability_set
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
	var forward := {}
	var queue: Array[Ledge] = [start]
	reached[start] = true
	while not queue.is_empty():
		var ledge: Ledge = queue.pop_back()
		_ensure_edges(_rooms[ledge.room_id])
		var next: Array[Ledge] = []
		for index in ledge.to_ledges:
			next.append(_ledges[ledge.room_id][index])
		for index in ledge.to_doors:
			reached_doors["%s#%d" % [ledge.room_id, index]] = true
			var arrival := _arrival(ledge.room_id, index)
			if arrival == null:
				var door: Door = (_rooms[ledge.room_id] as RoomInfo).exits[index]
				report.errors.append("Room %s: the %s door at %s leads into room %s, but nothing there is standable at its far side" % [ledge.room_id, door.edge, door.rect, door.dest_id])
				continue
			next.append(arrival)
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
	var traps: Array[String] = []
	var unreached_ledges: Array[String] = []
	for id in _rooms:
		var info: RoomInfo = _rooms[id]
		for i in info.exits.size():
			if reached_rooms.has(id) and not reached_doors.has("%s#%d" % [id, i]):
				var door := info.exits[i]
				lost_doors.append("Room %s: the %s door at %s cannot be reached" % [id, door.edge, door.rect])
				report.unreached_doors.append([String(id), door])
		for ledge: Ledge in _ledges[id]:
			if not reached.has(ledge):
				report.unreached.append(ledge)
				if reached_rooms.has(id):
					unreached_ledges.append("%s cannot be reached" % ledge.describe())
			elif not home.has(ledge):
				report.traps.append(ledge)
				traps.append("%s is a trap: once there, no path leads back to the start" % ledge.describe())
	_append_capped(report.errors, lost_doors)
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
			# end, unless a wall stops it first.
			ledge.lo = float(ledge.x0) * cell + (cell * 0.5 if info.is_solid(ledge.x0 - 1, y) else -cell * 0.5 + 0.01)
			ledge.hi = float(ledge.x1 + 1) * cell + (-cell * 0.5 if info.is_solid(ledge.x1 + 1, y) else cell * 0.5 - 0.01)
			out.append(ledge)
	return out


func _standable(info: RoomInfo, x: int, y: int) -> bool:
	return not info.is_solid(x, y) and info.is_solid(x, y + 1)


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


func _arrival(room_id: String, door_index: int) -> Ledge:
	var key := "%s#%d" % [room_id, door_index]
	if not _arrivals.has(key):
		var door: Door = (_rooms[room_id] as RoomInfo).exits[door_index]
		var dest: RoomInfo = _rooms[door.dest_id]
		_arrivals[key] = _ledge_at_cell(dest, dest.stand_cell_for_rect(door.dest_rect))
	return _arrivals[key]


# --- edges ----------------------------------------------------------------


func _ensure_edges(info: RoomInfo) -> void:
	if _solved.has(info.id):
		return
	_solved[info.id] = true
	var rects: Array[Rect2] = []
	for cell_rect in info.solids:
		rects.append(Grid.cell_rect(cell_rect))
	var triggers: Array[Rect2] = []
	for door in info.exits:
		triggers.append(door.trigger_rect())
	var bounds := Rect2(Vector2(-40.0, -120.0), info.pixel_size + Vector2(80.0, 160.0))
	for ledge: Ledge in _ledges[info.id]:
		_walk_to_doors(ledge, triggers)
		var near := _near(rects, ledge)
		for x in _start_xs(ledge):
			for input in [-1.0, 0.0, 1.0]:
				var speed := _run_speed(ledge, x, input)
				for hold in HOLDS:
					_try(info, ledge, near, triggers, bounds, x, speed, input, hold, true)
		_walk_off(info, ledge, near, triggers, bounds)


func _walk_to_doors(ledge: Ledge, triggers: Array[Rect2]) -> void:
	var half := float(Grid.CELL) * 0.5
	for i in triggers.size():
		var trigger := triggers[i]
		var overlaps_height := trigger.position.y < ledge.top and trigger.end.y > ledge.top - float(Grid.CELL)
		var overlaps_width := ledge.hi + half > trigger.position.x and ledge.lo - half < trigger.end.x
		if overlaps_height and overlaps_width:
			ledge.add_door(i)


## Solids close enough to matter, so each simulated frame has fewer to test.
func _near(rects: Array[Rect2], ledge: Ledge) -> Array[Rect2]:
	var span := Rect2(ledge.lo - REACH_X, ledge.top - REACH_UP, ledge.hi - ledge.lo + REACH_X * 2.0, REACH_UP + REACH_DOWN)
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


func _walk_off(info: RoomInfo, ledge: Ledge, near: Array[Rect2], triggers: Array[Rect2], bounds: Rect2) -> void:
	var cell := float(Grid.CELL)
	if not info.is_solid(ledge.x1 + 1, ledge.row):
		var edge := float(ledge.x1 + 1) * cell - 1.0
		_try(info, ledge, near, triggers, bounds, edge, _cfg.run_speed, 1.0, 0, false)
		_try(info, ledge, near, triggers, bounds, edge, _cfg.run_speed, 0.0, 0, false)
	if not info.is_solid(ledge.x0 - 1, ledge.row):
		var edge := float(ledge.x0) * cell + 1.0
		_try(info, ledge, near, triggers, bounds, edge, -_cfg.run_speed, -1.0, 0, false)
		_try(info, ledge, near, triggers, bounds, edge, -_cfg.run_speed, 0.0, 0, false)


func _try(info: RoomInfo, ledge: Ledge, near: Array[Rect2], triggers: Array[Rect2], bounds: Rect2, x: float, speed: float, input: float, hold: int, jump: bool) -> void:
	var start := Vector2(x, ledge.top - float(Grid.CELL) * 0.5)
	var result := MovementSim.simulate_jump(_cfg, near, start, Vector2(speed, 0.0), input, hold, true, jump, triggers, bounds)
	var door := int(result["trigger"])
	if door >= 0:
		ledge.add_door(door)
	elif result["landed"]:
		var target := _ledge_at_position(info, result["position"])
		if target != null and target != ledge:
			ledge.add_ledge(target.index)


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
	var to_doors: Array[int] = []

	func add_ledge(target: int) -> void:
		if not to_ledges.has(target):
			to_ledges.append(target)

	func add_door(door: int) -> void:
		if not to_doors.has(door):
			to_doors.append(door)

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
