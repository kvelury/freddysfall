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
	save.write("7", Grid.cell_center(Vector2i(7, 70)))
	var original := FileAccess.get_file_as_string(TEMP)
	var output: Array[String] = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/dev_session_test.gd", "--", "--dev", "--room=7", "--new-game", "--boot-probe"], output, true)
	_check(result == 0, "actual dev launch starts fresh and new-game cannot erase the save: %s" % "".join(output).strip_edges())
	state.reset()
	_world = load("res://src/world/world.tscn").instantiate()
	_world.start_override = "7"
	root.add_child(_world)
	await process_frame
	_world.player.scripted = true
	_check(state.health == 0 and state.abilities.imprint_width == 2, "direct room starts with fresh state, not the save")
	_check(session.enter(_world).is_empty() and session.isolated(), "enter protected dev mode")
	_check(not save.write("7", Vector2.ZERO) and save.load_game().is_empty(), "normal save reads and writes are blocked")
	save.erase()
	_check(FileAccess.get_file_as_string(TEMP) == original, "erase cannot delete a normal save during a test")
	var error: String = session.apply(_world, {"abilities": {"imprint_unlocked": true, "imprint_width": 5, "imprint_max_active": 2}, "tokens": 3, "health": 4})
	_check(error.is_empty() and state.tokens == 3 and state.health == 4 and state.abilities.imprint_width == 5, "grant powers and resources exactly")
	_world.imprint.platforms.append(ImprintPlatform.new(Rect2(10, 10, 20, 10), 2.5))
	state.tokens = 1
	_check(session.apply(_world, {"health": 6}).is_empty() and _world.imprint.platforms.size() == 1, "resource edits leave Imprints alone")
	_check(state.max_health == 6, "more pips than the bar holds lengthens the bar")
	_check(session.apply(_world, {"max_health": 8}).is_empty() and state.max_health == 8 and state.health == 6 and session.loadout["max_health"] == 8, "the bar can be longer than the pips held")
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

	# The Classic Imprint switch: a comparison, for a dev test only.
	_check(not session.classic_imprint and not session.classic_imprint_active(), "Classic Imprint starts off")
	_world.imprint.platforms.append(ImprintPlatform.new(Rect2(10, 10, 30, 10), 1.5))
	_world.imprint.cooldown_left = 2.0
	_check(session.set_classic_imprint(_world, true).is_empty() and session.classic_imprint and session.classic_imprint_active(), "Classic Imprint can be turned on in a dev test")
	_check(_world.imprint.platforms.is_empty() and is_zero_approx(_world.imprint.cooldown_left), "and turning it on clears platforms and the cooldown")
	_world.imprint.platforms.append(ImprintPlatform.new(Rect2(10, 10, 30, 10), 1.5, false))
	_check(session.set_classic_imprint(_world, false).is_empty() and not session.classic_imprint_active() and _world.imprint.platforms.is_empty(), "turning it off clears them too")
	_check(not _dict_has_classic(state.to_dict()) and not _dict_has_classic(session.loadout) and not _dict_has_classic(session.baseline), "it is in no save, loadout or baseline")
	session.mode = session.Mode.NORMAL
	_check(not session.set_classic_imprint(_world, true).is_empty() and not session.classic_imprint, "it is refused outside a dev test")
	session.classic_imprint = true
	_check(not session.classic_imprint_active(), "and a flag left set does nothing outside a dev test")
	session.classic_imprint = false
	session.mode = session.Mode.DEV_TEST

	# The token marks switch: off unless a dev test turns it on.
	var body: PlayerBody = _world.player._visual
	state.tokens = 3
	_check(not session.token_marks and not session.token_marks_active() and body.shown_tokens() == 0, "token marks start off: the body shows none of the 3 tokens carried")
	var redraws := [0]
	session.token_marks_changed.connect(func() -> void: redraws[0] += 1)
	_check(session.set_token_marks(_world, true).is_empty() and session.token_marks_active() and redraws[0] == 1, "token marks can be turned on in a dev test, and tell the body")
	_check(body.shown_tokens() == 3 and session.status_line().contains("token marks"), "and then the body shows all 3, and the status line says so (%s)" % session.status_line())
	state.tokens = 1
	_check(body.shown_tokens() == 1, "it follows the tokens carried")
	state.abilities.imprint_unlocked = true
	_check(not body.shown_imprint(), "the Imprint line is never drawn, with Imprint found and the token marks on")
	state.abilities.imprint_unlocked = false
	_check(not _dict_has_key(state.to_dict(), "token_marks") and not _dict_has_key(session.loadout, "token_marks") and not _dict_has_key(session.baseline, "token_marks"), "it is in no save, loadout or baseline")
	session.mode = session.Mode.NORMAL
	_check(not session.set_token_marks(_world, false).is_empty() and session.token_marks, "it is refused outside a dev test")
	_check(not session.token_marks_active() and body.shown_tokens() == 0 and not session.status_line().contains("token marks"), "and a flag left set shows nothing outside a dev test")
	session.mode = session.Mode.DEV_TEST
	_check(session.set_token_marks(_world, false).is_empty() and body.shown_tokens() == 0, "turning it off hides them again")
	state.tokens = 0

	state.flags["pickup:baseline"] = true
	state.machines["baseline_machine"] = 1
	_check(session.start(_world, "7").is_empty(), "start a repeatable test")
	await _replacement()
	_check(state.tokens == 3 and state.health == 6, "starting a test replenishes the selected resources")
	_world.warp_to("3")
	state.flags["pickup:later"] = true
	state.machines["baseline_machine"] = 3
	state.tokens = 0
	state.health = 0
	var pip := EntityDef.new()
	pip.type = "health"
	pip.id = "later_pip"
	state.take_health(pip)
	_check(state.health == 1 and state.flags.has("health:later_pip"), "taking a health pip in a test adds one and sets its flag")
	state.map_zoom = 2
	_check(session.set_classic_imprint(_world, true).is_empty(), "turn Classic Imprint on before a retry")
	_check(session.set_token_marks(_world, true).is_empty(), "and the token marks")
	_check(session.wall_strength() == 3 and session.set_wall_strength(_world, 5).is_empty() and session.wall_strength() == 5, "wall strength starts at 3 and a dev test can set it")
	_check(not state.to_dict().has("wall_strength") and not session.loadout.has("wall_strength"), "it is in no save or loadout")
	_check(session.retry(_world).is_empty(), "retry after travelling across rooms")
	await _replacement()
	_check(session.wall_strength() == 5, "wall strength survives a retry")
	_check(session.classic_imprint and session.classic_imprint_active(), "Classic Imprint survives a retry")
	_check(session.token_marks_active() and _world.player._visual.shown_tokens() == state.tokens, "and so do the token marks, on the new body")
	_check(_world.current.info.id == "7" and state.flags.has("pickup:baseline") and not state.flags.has("pickup:later") and state.machines["baseline_machine"] == 1 and not state.flags.has("health:later_pip"), "retry restores original room, flags (the pip is back), and machine fills")
	_check(state.tokens == 3 and state.health == 6 and state.max_health == 8 and state.abilities.imprint_duration == 5.0, "retry uses latest explicitly applied powers and replenishes resources")
	_check(is_equal_approx(state.abilities.imprint_cooldown, 0.2) and is_zero_approx(_world.imprint.cooldown_left), "retry keeps the applied cooldown setting, with no cooldown running")
	_check(_world.current.tick == 0 and _world.imprint.platforms.is_empty() and _world.player.velocity == Vector2.ZERO, "rebuild resets platform clock and transient player state")
	_check(not state.visited.has("3") and state.map_zoom == 1, "retry restores visited rooms and map zoom")
	session.set_retry_on_death(_world, true)
	_world._die()
	await create_timer(0.8).timeout
	_world = _current_world()
	_world.player.scripted = true
	_check(_world.current.info.id == "7" and state.health == 6 and not _world.is_busy(), "automatic death retry refills health and finishes the death effect")
	session.set_retry_on_death(_world, false)
	_world._die()
	await create_timer(0.8).timeout
	_check(state.health == 5 and state.max_health == 8 and not _world.is_busy(), "with automatic retry off, death empties a pip and the bar keeps its length")
	state.health = 0
	session.set_retry_on_death(_world, true)
	_world._die()
	await create_timer(0.8).timeout
	_world = _current_world()
	_world.player.scripted = true
	_check(_world.current.info.id == "7" and state.health == 6, "automatic retry also works with no health")
	_check(session.start(_world, "7", true).is_empty(), "start a fresh test")
	await _replacement()
	_check(state.flags.is_empty() and state.machines.is_empty() and state.tokens == 3, "fresh test clears progression and retains the selected loadout")
	_world.save_now()
	_check(FileAccess.get_file_as_string(TEMP) == original, "all playtest operations preserve the save bytes")
	_check(session.end(_world).is_empty(), "end isolated playtest")
	await _replacement()
	_check(not session.classic_imprint and not session.classic_imprint_active(), "ending the playtest resets Classic Imprint")
	_check(session.wall_strength() == 3 and session.wall_strength_override == 0, "and the wall strength")
	_check(not session.token_marks and _world.player._visual.shown_tokens() == 0, "and the token marks")
	_check(not session.isolated() and state.health == 7 and state.abilities.imprint_width == 4 and _world.current.info.id == "7", "ending restores normal saved progression")
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


## Whether a dictionary holds the switch anywhere, however deep.
func _dict_has_classic(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if String(key).contains("classic") or _dict_has_classic(value[key]):
				return true
	return false


## Whether a dictionary holds `name` as a key anywhere, however deep.
func _dict_has_key(value: Variant, name: String) -> bool:
	if value is Dictionary:
		for key in value:
			if String(key) == name or _dict_has_key(value[key], name):
				return true
	return false


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
	_check(session.isolated() and world.current.info.id == "7" and state.health == 0 and state.flags.is_empty(), "direct dev boot resets progression")
	_check(FileAccess.get_file_as_string(TEMP) == original, "new-game is ignored in isolated startup")
	world.free()
	quit(0 if _ok else 1)
