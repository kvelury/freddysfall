extends SceneTree

## The player and the reach solver have to move the same. Each case replays one
## input plan through the real Player node and through MovementSim.simulate_jump
## in room 1, and the two must end in the same place.

const TOLERANCE := 0.01


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "1"
	root.add_child(world)
	await process_frame
	# Stop the world ticking by itself, so the test is the only thing moving.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Player = world.get_node("Player")
	player.scripted = true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var rects: Array[Rect2] = world.current.world_rects()

	var ok := true
	# [start, input, jump held for this many ticks, running start]
	var cases := [
		[Vector2(25, 165), 1.0, 90, true, "floor to the left platform"],
		[Vector2(25, 165), 1.0, 3, true, "a tap from the floor"],
		[Vector2(100, 125), 1.0, 90, true, "left platform to the middle"],
		[Vector2(180, 85), 1.0, 90, true, "middle platform to the exit ledge"],
		[Vector2(150, 165), -1.0, 90, true, "floor, leaping left"],
		[Vector2(150, 165), 0.0, 90, false, "straight up"],
		[Vector2(58, 165), 1.0, 90, true, "clipping a ceiling corner from the left"],
		[Vector2(112, 165), -1.0, 90, true, "clipping a ceiling corner from the right"],
		[Vector2(112, 125), 1.0, 8, true, "off a platform edge with a short hop"],
	]
	for c in cases:
		ok = _case(player, cfg, rects, c[0], c[1], c[2], c[3], c[4]) and ok
	print("PARITY %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _case(player: Player, cfg: MovementConfig, rects: Array[Rect2], start: Vector2, input: float, hold: int, running: bool, label: String) -> bool:
	var speed := input * cfg.run_speed if running else 0.0
	var expected := MovementSim.simulate_jump(cfg, rects, start, Vector2(speed, 0.0), input, hold)
	player.place(start, rects)
	player.velocity = Vector2(speed, 0.0)
	var airborne := false
	var landed := false
	for frame in 180:
		player.scripted_x = input
		player.scripted_jump_pressed = frame == 0
		player.scripted_jump_held = frame < hold
		player._physics_process(1.0 / 60.0)
		if not player.is_on_floor():
			airborne = true
		elif frame > 2 and airborne:
			landed = true
			break
	var gap := player.global_position.distance_to(expected["position"])
	var same := landed == bool(expected["landed"]) and gap <= TOLERANCE
	return _check(same and landed, "%s: player %s, solver %s (%.4f px apart)" % [label, player.global_position, expected["position"], gap])


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
