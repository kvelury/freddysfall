extends SceneTree

## Moving platforms. The room format: a platform drawn as a row of its glyph
## with its track (- or |) running on to where it turns, and every rule the
## parser keeps around it. The path: where it is at each tick, waiting at
## each end. Play: a rider is carried exactly, walks on it, and leaves it with
## only their own velocity unless the config says otherwise; a platform that
## pushes a body into a wall crushes it; dying while riding comes back on real
## floor. Parity: the real player and MovementSim agree with a platform
## moving. The solver: a ledge only a ride reaches is reached, a platform out
## of reach is warned about, and an Imprint is refused on a track.

const DT := 1.0 / 60.0
const TOLERANCE := 0.01


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(120.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := true
	ok = _parser() and ok
	ok = _path() and ok
	ok = _crush() and ok
	ok = _solver() and ok
	ok = await _play() and ok
	ok = await _dying_while_riding() and ok
	print("PLATFORM %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


# --- the room format -------------------------------------------------------


func _parser() -> bool:
	var ok := true
	var row := "#.....LLLLL--------------------#"
	var info := _load({Vector2i(0, 14): row}, "  L = platform id=p1 speed=60 pause=0.2\n")
	ok = _check(info != null and info.platforms.size() == 1, "a platform with a track to its right loads") and ok
	if info != null and info.platforms.size() == 1:
		var path := info.platforms[0]
		ok = _check(path.start_cells == Rect2i(6, 14, 5, 1) and path.direction == Vector2i.RIGHT and path.cells == 20, "drawn at cells 6-10 of row 14, running 20 cells right (%s, %s, %d)" % [path.start_cells, path.direction, path.cells]) and ok
		ok = _check(path.travel_ticks == 200 and path.pause_ticks == 12 and path.period() == 424, "200 px at 60 px/s is 200 ticks, with 12 ticks of pause each end (%d, %d)" % [path.travel_ticks, path.pause_ticks]) and ok
		ok = _check(info.entities.size() == 1 and info.entities[0].type == "platform" and info.entities[0].cell == Vector2i(6, 14), "and it is one thing in the legend, at its first cell") and ok
	info = _load({Vector2i(0, 14): "#--------------------LLLLL.....#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(info != null and info.platforms.size() == 1 and info.platforms[0].direction == Vector2i.LEFT and info.platforms[0].pause_ticks == 12, "a track to its left runs left, and pause defaults to 0.2 s") and ok
	var up := {Vector2i(0, 15): "#.........LLL..................#"}
	for y in range(10, 15):
		up[Vector2i(0, y)] = "#.........|||..................#"
	info = _load(up, "  L = platform id=p1 speed=40 pause=0\n")
	ok = _check(info != null and info.platforms.size() == 1 and info.platforms[0].direction == Vector2i.UP and info.platforms[0].cells == 5, "a | track above it runs up") and ok

	var errors := _errors({Vector2i(0, 14): "#.....LLLLL....................#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "has no track"), "a platform with no track is an error") and ok
	errors = _errors({Vector2i(0, 14): "#..---LLLLL--------............#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "more than one side"), "track on both ends is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LL.LL--------............#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "has a gap"), "a platform with a gap is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 15): "#.....L........................#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "more than one row"), "a platform on two rows is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------....---.....#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "belongs to no moving platform"), "a stray piece of track is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 13): "#..............#...............#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "needs open air in the row above"), "something solid in the row a rider stands in is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 13): "#.........^....................#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "needs open air in the row above"), "and so are spikes there") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 13): "#.........T....................#"}, "  L = platform id=p1 speed=60\n  T = token id=t1\n")
	ok = _check(_has(errors, "needs open air in the row above"), "and so is a token there") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#"}, "  L = platform id=p1\n")
	ok = _check(_has(errors, "needs speed="), "a platform needs a speed") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 16): "#.............--...............#"}, "  L = platform id=p1 speed=60\n")
	ok = _check(_has(errors, "belongs to no moving platform"), "track not joined to a platform is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#"}, "  L = platform id=p1 speed=0\n")
	ok = _check(_has(errors, "a number above 0"), "a speed of 0 is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#"}, "  L = platform id=p1 speed=60 pause=-1\n")
	ok = _check(_has(errors, "0 or more"), "a pause below 0 is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 13): "#............MMM-----..........#"}, "  L = platform id=p1 speed=60\n  M = platform id=p2 speed=60\n")
	ok = _check(_has(errors, "needs open air in the row above"), "another platform in the row above a track is an error") and ok
	errors = _errors({Vector2i(0, 14): "#.....LLLLL--------............#", Vector2i(0, 16): "#.........M....................#"}, "  L = platform id=p1 speed=60\n  M = machine id=m1 upgrade=imprint\n")
	ok = _check(_has(errors, "in the way of moving platform"), "a 3TM in a platform's way is an error") and ok

	# A door: the track has to stay a cell clear of it.
	var near_door := {Vector2i(0, 14): "XLLLLL---------................#", Vector2i(0, 15): "X..............................#", Vector2i(0, 16): "X..............................#"}
	var entries := [
		{"id": "1", "grid_pos": Vector2i(1, 0), "text": "legend:\n  L = platform id=p1 speed=60\n---\n" + _room(near_door, Vector2i(2, 16))},
		{"id": "2", "grid_pos": Vector2i(0, 0), "text": _room({Vector2i(0, 14): "#..............................X", Vector2i(0, 15): "#..............................X", Vector2i(0, 16): "#..............................X"}, Vector2i(-1, -1))},
	]
	errors.clear()
	RoomParser.build(entries, "1", errors)
	ok = _check(_has(errors, "clear of doorways"), "a track next to a door is an error") and ok

	var save_entries := [{"id": "s9", "grid_pos": Vector2i.ZERO, "text": "legend:\n  S = save id=s9_save\n  L = platform id=p1 speed=60\n---\n" + _room({Vector2i(0, 16): "#...............S..............#", Vector2i(0, 10): "#.....LLLLL--------............#"}, Vector2i(2, 16))}]
	errors.clear()
	RoomParser.build(save_entries, "s9", errors)
	ok = _check(_has(errors, "has a moving platform"), "a save room cannot have a moving platform") and ok
	return ok


# --- the path --------------------------------------------------------------


func _path() -> bool:
	var ok := true
	var path := PlatformPath.new("p", Rect2i(6, 14, 5, 1), Vector2i.RIGHT, 20, 60.0, 0.2)
	var x := func(tick: int) -> float: return path.rect_at(tick).position.x
	ok = _check(x.call(0) == 60.0 and x.call(11) == 60.0, "it waits at the end it is drawn at first (%.1f, %.1f)" % [x.call(0), x.call(11)]) and ok
	ok = _check(is_equal_approx(x.call(12 + 100), 160.0), "slides at 60 px/s: halfway after 100 ticks of travel (%.2f)" % x.call(112)) and ok
	ok = _check(x.call(212) == 260.0 and x.call(223) == 260.0, "waits at the far end (%.1f, %.1f)" % [x.call(212), x.call(223)]) and ok
	ok = _check(is_equal_approx(x.call(224 + 100), 160.0) and x.call(424) == 60.0 and x.call(424 + 5) == 60.0, "and comes back, and starts over") and ok
	ok = _check(path.rect_at(50).position.y == 140.0 and path.rect_at(50).size == Vector2(50, 10), "it keeps its row and its size") and ok
	var still := PlatformPath.new("q", Rect2i(0, 0, 1, 1), Vector2i.DOWN, 3, 30.0, 0.0)
	ok = _check(still.pause_ticks == 0 and still.travel_ticks == 60 and still.period() == 120 and still.rect_at(60).position.y == 30.0, "with no pause it turns straight round (%d)" % still.period()) and ok
	ok = _check(path.swept_cells() == Rect2i(6, 14, 25, 1) and path.band_cells() == Rect2i(6, 13, 25, 1), "it sweeps cells 6-30 and keeps row 13 above them clear") and ok
	return ok


# --- pushing and crushing -------------------------------------------------


func _crush() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var rects: Array[Rect2] = [Rect2(0, 0, 10, 180), Rect2(0, 170, 320, 10)]
	# A platform at floor height slides left into a body standing by the wall.
	var movers := Movers.new([PlatformPath.new("p", Rect2i(4, 16, 3, 1), Vector2i.LEFT, 4, 60.0, 0.0)])
	var s := MovementSim.State.new()
	s.position = Vector2(15, 165)
	s.grounded = true
	var crushed := false
	for tick in 120:
		MovementSim.step(cfg, s, rects, 0.0, false, false, DT, movers, tick)
		if s.crushed:
			crushed = true
			break
	ok = _check(crushed, "a platform that pushes a body into a wall crushes it") and ok
	# In the open the same platform only pushes.
	movers = Movers.new([PlatformPath.new("p", Rect2i(14, 16, 3, 1), Vector2i.LEFT, 4, 60.0, 0.0)])
	s = MovementSim.State.new()
	s.position = Vector2(125, 165)
	s.grounded = true
	crushed = false
	var start_x := s.position.x
	for tick in 50:
		MovementSim.step(cfg, s, rects, 0.0, false, false, DT, movers, tick)
		crushed = crushed or s.crushed
	ok = _check(not crushed and s.position.x < start_x - 9.0, "in the open it pushes the body along instead (%.1f to %.1f)" % [start_x, s.position.x]) and ok
	# A platform rising under a body lifts it and carries it.
	movers = Movers.new([PlatformPath.new("p", Rect2i(10, 16, 3, 1), Vector2i.UP, 3, 30.0, 0.0)])
	s = MovementSim.State.new()
	s.position = Vector2(115, 155)
	var rode := false
	for tick in 60:
		MovementSim.step(cfg, s, rects, 0.0, false, false, DT, movers, tick)
		rode = rode or s.riding == 0
	ok = _check(rode and is_equal_approx(s.position.y + MovementSim.HALF.y, movers.rect(0, 60).position.y), "a body on a rising platform rides it up (feet at %.1f, platform at %.1f)" % [s.position.y + 5.0, movers.rect(0, 60).position.y]) and ok
	return ok


# --- the solver ------------------------------------------------------------


func _solver() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	# A ledge 8 cells up on the right is too high to jump to, but a platform
	# that rises beside it brings it within a jump.
	var marks := {Vector2i(0, 9): "#........................#######", Vector2i(0, 15): "#.................LLL..........#"}
	for y in range(10, 15):
		marks[Vector2i(0, y)] = "#.................|||..........#"
	var rooms := _rooms(marks, "  L = platform id=lift speed=40\n")
	var graph := ReachGraph.new(rooms, cfg)
	var report := graph.analyze("1")
	var high: ReachGraph.Ledge = null
	var lift: ReachGraph.Ledge = null
	for ledge in graph.ledges_in("1"):
		if ledge.row == 8 and not ledge.moving:
			high = ledge
		if ledge.moving:
			lift = ledge
	ok = _check(lift != null and report.reached.has(lift), "the rising platform is reached from the floor") and ok
	ok = _check(high != null and report.reached.has(high), "and the high ledge is reached by riding it") and ok
	ok = _check(report.errors.is_empty(), "with no errors, so there is a way back down from both %s" % [report.errors]) and ok
	var plain := {Vector2i(0, 9): "#........................#######"}
	rooms = _rooms(plain, "")
	graph = ReachGraph.new(rooms, cfg)
	report = graph.analyze("1")
	var reached_high := false
	for ledge in graph.ledges_in("1"):
		if ledge.row == 8 and report.reached.has(ledge):
			reached_high = true
	ok = _check(not reached_high, "without the platform the high ledge is out of reach") and ok
	# A platform nine cells up cannot be reached.
	rooms = _rooms({Vector2i(0, 8): "#.........LLL--------..........#"}, "  L = platform id=sky speed=60\n")
	graph = ReachGraph.new(rooms, cfg)
	report = graph.analyze("1")
	ok = _check(_has(report.warnings, "the moving platform sky cannot be reached"), "a platform out of reach is a warning %s" % [report.warnings]) and ok
	# Imprint is refused on a track and in the row above it.
	var info: RoomInfo = rooms["1"]
	var body := Rect2(20, 160, 10, 10)
	ok = _check(ImprintRules.check(info, Vector2i(15, 8), 2, body) == "platform" and ImprintRules.check(info, Vector2i(15, 7), 2, body) == "platform", "an Imprint cannot go on a track or in the row above it") and ok
	ok = _check(ImprintRules.check(info, Vector2i(15, 10), 2, body).is_empty(), "but can go below it") and ok
	return ok


# --- play ------------------------------------------------------------------


func _play() -> bool:
	var ok := true
	var world := await _world()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	var cfg := player.config
	var original := cfg.inherit_platform_velocity
	ok = _check(room.info.id == "7" and room.movers.size() == 1, "room 7 has one moving platform") and ok
	var node: MovingPlatform = null
	for child in room.get_children():
		if child is MovingPlatform:
			node = child
	ok = _check(node != null and node.position == room.info.platforms[0].rect_at(room.tick).position, "drawn where its path has it") and ok

	# Standing on it: carried exactly, through a whole trip.
	_put_on(room, player, 25.0)
	_tick(room, player)
	ok = _check(player.riding() == 0, "a player put on it stands on it") and ok
	var offset := player.global_position.x - room.mover_rects()[0].position.x
	var worst := 0.0
	var always := true
	var period := room.info.platforms[0].period()
	for i in period:
		_tick(room, player)
		worst = maxf(worst, absf(player.global_position.x - room.mover_rects()[0].position.x - offset))
		always = always and player.riding() == 0 and is_equal_approx(player.global_position.y + MovementSim.HALF.y, room.mover_rects()[0].position.y)
	ok = _check(always and worst < TOLERANCE, "standing still, it carries them there and back and they stay where they stood on it (%.4f px off)" % worst) and ok

	# Walking on it moves them along it.
	var before := player.global_position.x - room.mover_rects()[0].position.x
	player.scripted_x = -1.0
	for i in 10:
		_tick(room, player)
	player.scripted_x = 0.0
	var moved := (player.global_position.x - room.mover_rects()[0].position.x) - before
	ok = _check(player.riding() == 0 and moved < -5.0, "walking moves them along it (%.1f px)" % moved) and ok

	# With the switch off, jumping off while it moves keeps only their own velocity.
	cfg.inherit_platform_velocity = false
	_until_moving(room, player)
	var jumped := _jump(room, player)
	ok = _check(jumped["left"] and absf(jumped["vx"]) < TOLERANCE and jumped["drift"] < TOLERANCE, "with inherit_platform_velocity off, jumping off while it moves keeps only their own speed: none (%.2f px/s, drifted %.3f px)" % [jumped["vx"], jumped["drift"]]) and ok

	# With the switch on, the platform's velocity is added.
	cfg.inherit_platform_velocity = true
	_put_on(room, player, 25.0)
	_until_moving(room, player)
	var platform_v := room.movers.step_of(0, room.tick) / DT
	jumped = _jump(room, player)
	cfg.inherit_platform_velocity = original
	ok = _check(jumped["left"] and absf(jumped["vx"] - platform_v.x) < 0.5, "with inherit_platform_velocity on, they leave at the platform's speed (%.2f px/s, platform %.2f)" % [jumped["vx"], platform_v.x]) and ok

	ok = _check(not original, "the game ships with inherit_platform_velocity off (movement.tres)") and ok

	# Parity: the real player and the solver's simulation agree, with whatever
	# the game ships with.
	ok = _parity(room, player, cfg) and ok
	# Step off the returning platform's left edge onto the clear landing.
	room.tick = 0
	_put_on(room, player, 5.0)
	player.scripted_x = -1.0
	for i in 45:
		_tick(room, player)
	player.scripted_x = 0.0
	var local: Vector2 = player.global_position - room.position
	ok = _check(player.is_on_floor() and player.riding() == -1 and is_equal_approx(local.y, _floor_y(room)) and local.x + MovementSim.HALF.x <= 150.0, "stepping left off the platform returns to safe floor (%s)" % local) and ok
	world.queue_free()
	await process_frame
	return ok


## The player and MovementSim, from the same tick, with the same input.
func _parity(room: Room, player: Player, cfg: MovementConfig) -> bool:
	var ok := true
	var rects: Array[Rect2] = room.world_rects()
	# From the floor onto the platform: find a standing start on the strip, at
	# some moment of its trip, whose full jump lands on it, then replay that
	# jump through the real player.
	var period := room.info.platforms[0].period()
	var offset := -1
	var from_x := 0.0
	for t in period:
		for x in [115.0, 125.0, 135.0, 145.0]:
			var found := MovementSim.simulate_jump(cfg, rects, room.position + Vector2(x, _floor_y(room)), Vector2.ZERO, 1.0, 90, true, true, [], Rect2(), [], [], NAN, 0, 120, false, room.movers, t, -1)
			if found["landed"] and int(found["riding"]) == 0:
				offset = t
				from_x = x
				break
		if offset >= 0:
			break
	ok = _check(offset >= 0, "some full jump from the strip lands on it (tick %d of its trip, from x %.0f)" % [offset, from_x]) and ok
	if offset < 0:
		return false
	while posmod(room.tick, period) != offset:
		_tick(room, player)
	var start := room.position + Vector2(from_x, _floor_y(room))
	player.place(start, rects)
	var expected := MovementSim.simulate_jump(cfg, rects, start, Vector2.ZERO, 1.0, 90, true, true, [], Rect2(), [], [], NAN, 0, 120, false, room.movers, room.tick, -1)
	for frame in int(expected["frames"]):
		player.scripted_x = 1.0
		player.scripted_jump_pressed = frame == 0
		player.scripted_jump_held = frame < 90
		_tick(room, player)
	player.scripted_x = 0.0
	var gap := player.global_position.distance_to(expected["position"])
	ok = _check(expected["landed"] and int(expected["riding"]) == 0 and player.riding() == 0 and gap <= TOLERANCE, "a jump from the floor lands on it, in the game and in the solver alike (%.4f px apart)" % gap) and ok

	# Riding, then jumping off part way along.
	_until_moving(room, player)
	var at := player.global_position
	var vel := player.velocity
	expected = MovementSim.simulate_jump(cfg, rects, at, vel, -1.0, 8, true, true, [], Rect2(), [], [], NAN, 0, 20, false, room.movers, room.tick, 0)
	for frame in int(expected["frames"]):
		player.scripted_x = -1.0
		player.scripted_jump_pressed = frame == 0
		player.scripted_jump_held = frame < 8
		_tick(room, player)
	player.scripted_x = 0.0
	gap = player.global_position.distance_to(expected["position"])
	ok = _check(gap <= TOLERANCE, "a hop off it part way along ends in the same place in both (%.4f px apart)" % gap) and ok
	return ok


## With one pip of health, a player who rides out over the spikes and steps
## off dies, and comes back on the room's own floor, not on the platform.
func _dying_while_riding() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	state.health = 1
	var world := await _world()
	var player: Player = world.get_node("Player")
	player.scripted = true
	for i in 30:
		await physics_frame
	var room: Room = world.current
	_put_on(room, player, 25.0)
	for i in 40:
		await physics_frame
	ok = _check(player.riding() == 0 and room.movers.step_of(0, room.tick).x > 0.0, "riding out over the spikes") and ok
	player.scripted_x = 1.0
	var died := false
	for i in 240:
		await physics_frame
		if not player.visible:
			died = true
			break
	player.scripted_x = 0.0
	for i in 120:
		await physics_frame
		if player.visible and player.input_enabled and player.is_on_floor():
			break
	var local: Vector2 = player.global_position - (world.current as Room).position
	ok = _check(died and world.current.info.id == "7" and state.health == 0, "stepping off into the spikes spends the pip and stays in room 7") and ok
	ok = _check(player.is_on_floor() and player.riding() == -1 and is_equal_approx(local.y, _floor_y(world.current)) and local.x < 150.0, "and they come back on the floor by the door (%s)" % local) and ok
	# A crush is a death: the world checks it before the player's next step.
	state.health = 1
	player._state.crushed = true
	await physics_frame
	await physics_frame
	ok = _check(not player.visible and state.health == 0, "a player a platform crushes dies") and ok
	world.queue_free()
	await process_frame
	state.reset()
	return ok


# --- helpers ---------------------------------------------------------------


## The player centre while standing on the merged room's bottom floor.
func _floor_y(room: Room) -> float:
	return room.info.pixel_size.y - Grid.CELL - MovementSim.HALF.y


## One physics tick in the game's order: the room moves its platforms, then
## the player steps.
func _tick(room: Room, player: Player) -> void:
	room._physics_process(DT)
	player._physics_process(DT)


## Puts the player standing `x` pixels along the platform.
func _put_on(room: Room, player: Player, x: float) -> void:
	var rect := room.mover_rects()[0]
	player.place(Vector2(rect.position.x + x, rect.position.y - MovementSim.HALF.y), room.world_rects())


## Ticks until the platform is in the middle part of a slide, with the player
## still on it and stood still on it for a moment first.
func _until_moving(room: Room, player: Player) -> void:
	for i in 20:
		_tick(room, player)
	var path := room.info.platforms[0]
	for i in path.period():
		var p := path.progress(room.tick)
		if p > 0.2 and p < 0.8 and room.movers.step_of(0, room.tick) != Vector2.ZERO:
			return
		_tick(room, player)


## Jumps straight up from the platform and watches the next few ticks: whether
## they left it, their velocity across just after, and how far across they
## went in the air after that.
func _jump(room: Room, player: Player) -> Dictionary:
	player.scripted_x = 0.0
	player.scripted_jump_pressed = true
	player.scripted_jump_held = true
	_tick(room, player)
	var vx := player.velocity.x
	var left := player.riding() == -1 and not player.is_on_floor()
	var x := player.global_position.x
	var drift := 0.0
	if absf(vx) < TOLERANCE:
		for i in 10:
			_tick(room, player)
			drift = maxf(drift, absf(player.global_position.x - x))
	player.scripted_jump_held = false
	return {"left": left, "vx": vx, "drift": drift}


func _world() -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	return world


## A one-screen room with `rows` replacing whole rows, a start, and `legend`.
func _load(rows: Dictionary, legend: String) -> RoomInfo:
	var errors: Array[String] = []
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": "legend:\n" + legend + "---\n" + _room(rows, Vector2i(2, 16))}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
		return null
	return built["rooms"]["1"]


func _errors(rows: Dictionary, legend: String) -> Array[String]:
	var errors: Array[String] = []
	RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": "legend:\n" + legend + "---\n" + _room(rows, Vector2i(2, 16))}], "1", errors)
	return errors


func _rooms(rows: Dictionary, legend: String) -> Dictionary:
	var errors: Array[String] = []
	var header := "" if legend.is_empty() else "legend:\n" + legend + "---\n"
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": header + _room(rows, Vector2i(2, 16))}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
	return built["rooms"]


## A walled one-screen room. `rows` maps Vector2i(0, y) to a whole row; a
## start goes at `spawn` unless it is off the grid.
func _room(rows: Dictionary, spawn: Vector2i) -> String:
	var out: Array[String] = []
	for y in 18:
		var row := ""
		if rows.has(Vector2i(0, y)):
			row = rows[Vector2i(0, y)]
		else:
			for x in 32:
				row += "#" if x == 0 or y == 0 or x == 31 or y == 17 else "."
		if y == spawn.y and spawn.x >= 0:
			row = row.substr(0, spawn.x) + "P" + row.substr(spawn.x + 1)
		out.append(row)
	return "\n".join(out) + "\n"


func _has(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	print("  nothing containing '%s' in %s" % [fragment, lines])
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
