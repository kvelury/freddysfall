extends SceneTree

## Save isolation, exact editing, real door blocks, and reproducible retries.

const TEMP := "user://dev_session_test.json"
var _ok := true
var _world: Node


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	if OS.get_cmdline_user_args().has("--boot-probe"):
		_boot_probe()
	else:
		_run()


func _run() -> void:
	var state: Node = root.get_node("GameState")
	var session: Node = root.get_node("DevSession")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = true
	state.reset()
	state.health = 7
	state.abilities.imprint_width = 4
	save.write("8", Vector2(15, 165))
	var original := FileAccess.get_file_as_string(TEMP)
	var output: Array[String] = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/dev_session_test.gd", "--", "--dev", "--room=8", "--new-game", "--boot-probe"], output, true)
	_check(result == 0, "actual dev launch starts fresh and new-game cannot erase the save: %s" % "".join(output).strip_edges())
	state.reset()
	_world = load("res://src/world/world.tscn").instantiate()
	_world.start_override = "8"
	root.add_child(_world)
	await process_frame
	_world.player.scripted = true
	_check(state.health == 0 and state.abilities.imprint_width == 2, "direct room starts with fresh state, not the save")
	_check(session.enter(_world).is_empty() and session.isolated(), "enter protected dev mode")
	_check(not save.write("8", Vector2.ZERO) and save.load_game().is_empty(), "normal save reads and writes are blocked")
	save.erase()
	_check(FileAccess.get_file_as_string(TEMP) == original, "erase cannot delete a normal save during a test")
	var error: String = session.apply(_world, {"abilities": {"imprint_unlocked": true, "imprint_width": 5, "imprint_max_active": 2}, "tokens": 3, "health": 4})
	_check(error.is_empty() and state.tokens == 3 and state.health == 4 and state.abilities.imprint_width == 5, "grant powers and resources exactly")
	_world.imprint.platforms.append(ImprintPlatform.new(Rect2(10, 10, 20, 10), 2.5))
	state.tokens = 1
	_check(session.apply(_world, {"health": 6}).is_empty() and _world.imprint.platforms.size() == 1, "resource edits leave Imprints alone")
	_check(session.apply(_world, {"abilities": {"imprint_duration": 5.0}}).is_empty() and state.tokens == 1 and session.loadout["tokens"] == 3 and _world.imprint.platforms.is_empty(), "duration edit preserves consumed live tokens and selected retry tokens")
	_check(session.apply(_world, {"abilities": {"imprint_width": 2}}).is_empty() and state.abilities.imprint_width == 2, "dev editing can lower a normally monotonic upgrade")
	_world.imprint.platforms.append(ImprintPlatform.new(Rect2(10, 10, 20, 10), 1.5))
	_world.imprint.cooldown_left = 3.0
	_check(session.apply(_world, {"abilities": {"imprint_cooldown": 0.2}}).is_empty() and is_equal_approx(state.abilities.imprint_cooldown, 0.2) and is_equal_approx(session.loadout["abilities"]["imprint_cooldown"], 0.2), "a cooldown edit is applied and selected for retries")
	_check(_world.imprint.platforms.is_empty() and is_zero_approx(_world.imprint.cooldown_left), "and it clears live platforms and any running cooldown")
	_check(not session.apply(_world, {"abilities": {"imprint_cooldown": -1.0}}).is_empty() and is_equal_approx(state.abilities.imprint_cooldown, 0.2), "a negative cooldown is refused without changing anything")
	var before: Dictionary = state.to_dict()
	_check(not session.apply(_world, {"tokens": 2, "health": -1}).is_empty() and state.to_dict() == before, "invalid edits make no partial changes")
	_check(session.start(_world, "missing").contains("No such room") and not session.replacing, "invalid room leaves test untouched")

	_world.warp_to("2")
	_world.player.place(_world.current.position + Grid.cell_center(Vector2i(3, 4)), _world.current.world_rects())
	var blocked_count: int = _world.current.world_rects().size()
	_check(_world.current.locked and session.set_bypass(_world, true).is_empty(), "bypass opens an actually locked room")
	_check(not _world.current.locked and _world.current.world_rects().size() < blocked_count and state.flags.is_empty(), "bypass removes physical collisions without marking pickups")
	var door: Door = _world.current.info.exits[0]
	var doorway := Grid.cell_rect(door.rect)
	_world.player.place(_world.current.position + doorway.get_center(), _world.current.world_rects())
	_check(not session.set_bypass(_world, false).is_empty() and session.bypass, "cannot close a door on the player")
	_world.player.place(_world.current.position + Grid.cell_center(Vector2i(3, 4)), _world.current.world_rects())
	_check(session.set_bypass(_world, false).is_empty() and _world.current.locked and _world.current.world_rects().size() == blocked_count, "turning bypass off restores unmet requirements and collisions")

	state.flags["pickup:baseline"] = true
	state.machines["baseline_machine"] = 1
	_check(session.start(_world, "8").is_empty(), "start a repeatable test")
	await _replacement()
	_check(state.tokens == 3 and state.health == 6, "starting a test replenishes the selected resources")
	_world.warp_to("3")
	state.flags["pickup:later"] = true
	state.machines["baseline_machine"] = 3
	state.tokens = 0
	state.health = 0
	state.map_zoom = 2
	_check(session.retry(_world).is_empty(), "retry after travelling across rooms")
	await _replacement()
	_check(_world.current.info.id == "8" and state.flags.has("pickup:baseline") and not state.flags.has("pickup:later") and state.machines["baseline_machine"] == 1, "retry restores original room, flags, and machine fills")
	_check(state.tokens == 3 and state.health == 6 and state.abilities.imprint_duration == 5.0, "retry uses latest explicitly applied powers and replenishes resources")
	_check(is_equal_approx(state.abilities.imprint_cooldown, 0.2) and is_zero_approx(_world.imprint.cooldown_left), "retry keeps the applied cooldown setting, with no cooldown running")
	_check(_world.current.tick == 0 and _world.imprint.platforms.is_empty() and _world.player.velocity == Vector2.ZERO, "rebuild resets platform clock and transient player state")
	_check(not state.visited.has("3") and state.map_zoom == 1, "retry restores visited rooms and map zoom")
	session.set_retry_on_death(_world, true)
	_world._die()
	await create_timer(0.8).timeout
	_world = _current_world()
	_world.player.scripted = true
	_check(_world.current.info.id == "8" and state.health == 6 and not _world.is_busy(), "automatic death retry refills health and finishes the death effect")
	session.set_retry_on_death(_world, false)
	_world._die()
	await create_timer(0.8).timeout
	_check(state.health == 5 and not _world.is_busy(), "with automatic retry off, death spends health normally")
	state.health = 0
	session.set_retry_on_death(_world, true)
	_world._die()
	await create_timer(0.8).timeout
	_world = _current_world()
	_world.player.scripted = true
	_check(_world.current.info.id == "8" and state.health == 6, "automatic retry also works with no health")
	_check(session.start(_world, "8", true).is_empty(), "start a fresh test")
	await _replacement()
	_check(state.flags.is_empty() and state.machines.is_empty() and state.tokens == 3, "fresh test clears progression and retains the selected loadout")
	_world.save_now()
	_check(FileAccess.get_file_as_string(TEMP) == original, "all playtest operations preserve the save bytes")
	_check(session.end(_world).is_empty(), "end isolated playtest")
	await _replacement()
	_check(not session.isolated() and state.health == 7 and state.abilities.imprint_width == 4 and _world.current.info.id == "8", "ending restores normal saved progression")
	_check(FileAccess.get_file_as_string(TEMP) == original, "ending does not save test state")
	# The independent headless/test disable flag must survive ending a session.
	save.enabled = false
	session.enter(_world)
	session.end(_world)
	await _replacement()
	_check(not save.enabled and not session.isolated(), "ending never turns on an independently disabled save")
	# The final assertions may run inside the rebuilt scene's ready signal.
	_world.queue_free()
	for path in [TEMP, TEMP + ".bad"]:
		DirAccess.remove_absolute(path)
	print("DEV SESSION %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


func _replacement() -> void:
	# Observe reset state at scene readiness, before any physics ticks. Waiting
	# for rendered frames allows a machine-dependent number of physics steps.
	var next: Node = await root.child_entered_tree
	while not next.has_method("warp_to"):
		next = await root.child_entered_tree
	if not next.is_node_ready():
		await next.ready
	_world = next
	_world.player.scripted = true


func _current_world() -> Node:
	for child in root.get_children():
		if child.has_method("warp_to"):
			return child
	return null


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	_ok = condition and _ok


## Run in a separate actual command-line process so launch precedence is tested
## without mocking the argument parser or ever pointing at the real save.
func _boot_probe() -> void:
	var save: Node = root.get_node("Save")
	var state: Node = root.get_node("GameState")
	var session: Node = root.get_node("DevSession")
	save.path = TEMP
	save.enabled = true
	var original := FileAccess.get_file_as_string(TEMP)
	state.health = 99
	state.flags["old"] = true
	var world: Node = load("res://src/world/world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	_check(session.isolated() and world.current.info.id == "8" and state.health == 0 and state.flags.is_empty(), "direct dev boot resets progression")
	_check(FileAccess.get_file_as_string(TEMP) == original, "new-game is ignored in isolated startup")
	world.free()
	quit(0 if _ok else 1)
