extends SceneTree

## Imprint in the real game: locked until it is found, placed with a click,
## solid under the player, replaced by the next one, broken by time, and gone
## when the room is left or the player dies. Uses room 5, which has spikes.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "5"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var tool: Node = world.get_node("Imprint")
	player.scripted = true
	tool.scripted = true
	var room: Room = world.current
	var base := room.world_rects().size()

	tool.scripted_cell = Vector2i(3, 8)
	ok = _check(not tool.place() and tool.platforms.is_empty(), "before Imprint is found, a click does nothing") and ok
	state.abilities.imprint_unlocked = true

	# Preview looks. The player is on the floor at the left.
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	await physics_frame
	tool.scripted_cell = Vector2i(6, 13)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "reachable", "a platform a hop away looks reachable (%s)" % tool.preview_state()) and ok
	tool.scripted_cell = Vector2i(10, 3)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unreachable", "one far overhead looks unreachable (%s)" % tool.preview_state()) and ok
	tool.scripted_cell = Vector2i(10, 16)
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unavailable" and tool.preview_reason() == "spikes", "one on the spikes is unavailable (%s)" % tool.preview_reason()) and ok
	ok = _check(not tool.place() and tool.platforms.is_empty(), "and a click there does nothing") and ok

	# Placed by an input event, as the mouse button would.
	tool.scripted_cell = Vector2i(10, 14)
	var click := InputEventAction.new()
	click.action = "imprint"
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	await physics_frame
	ok = _check(tool.platforms.size() == 1, "the imprint action places a platform above the spikes") and ok
	ok = _check(player.solids.size() == base + 1, "and the player now collides with it (%d solids)" % player.solids.size()) and ok

	# A click never replaces a platform: while one stands, another does nothing.
	var standing: Rect2 = tool.platforms[0].rect
	tool.scripted_cell = Vector2i(19, 13)
	ok = _check(not tool.place() and tool.platforms.size() == 1 and tool.platforms[0].rect == standing, "a second click while one stands does nothing") and ok
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unavailable" and tool.preview_reason() == "limit", "and the cursor is the cross, for the limit (%s)" % tool.preview_reason()) and ok
	var age_before: float = tool.platforms[0].age
	for i in 3:
		Input.parse_input_event(click)
		await physics_frame
	ok = _check(tool.platforms.size() == 1 and tool.platforms[0].rect == standing and tool.platforms[0].age > age_before, "clicking again and again leaves the one platform ageing, not renewed") and ok
	tool.clear(false)
	tool.sync_solids()
	ok = _check(tool.place() and tool.platforms.size() == 1, "once it is gone another may go") and ok

	# A body dropped onto one in open air lands and stays.
	player.global_position = room.position + Vector2(200.0, 112.0)
	player.velocity = Vector2.ZERO
	var landed := false
	for i in 120:
		await physics_frame
		if player.is_on_floor() and absf(player.global_position.y - (room.position.y + 130.0 - 5.0)) < 0.6:
			landed = true
			break
	ok = _check(landed, "the player lands on it and stands there (%s)" % player.global_position) and ok

	# Not replaced: the first stays, and the player has the one platform to collide with.
	tool.scripted_cell = Vector2i(3, 6)
	player.place(room.position + Grid.cell_center(Vector2i(20, 3)), room.world_rects())
	tool.clear(false)
	tool.sync_solids()
	tool.scripted_cell = Vector2i(10, 14)
	tool.place()
	tool.scripted_cell = Vector2i(3, 6)
	ok = _check(not tool.place() and tool.platforms.size() == 1 and is_equal_approx(tool.platforms[0].rect.position.x, room.position.x + 100.0), "the first one stays when a second is tried") and ok
	ok = _check(player.solids.size() == base + 1, "and the player has one platform to collide with") and ok
	tool.clear(false)
	tool.sync_solids()
	tool.place()
	ok = _check(is_equal_approx(tool.platforms[0].rect.position.x, room.position.x + 30.0), "the next one goes where it is aimed once the first is gone") and ok

	# Time breaks it, and the player on it falls.
	tool.platforms[0].lifetime = 0.5
	player.global_position = room.position + Vector2(45.0, 20.0)
	player.velocity = Vector2.ZERO
	for i in 20:
		await physics_frame
	ok = _check(player.is_on_floor() and player.global_position.y < room.position.y + 60.0, "the player stands on it before it breaks (%s)" % player.global_position) and ok
	for i in 40:
		await physics_frame
	ok = _check(tool.platforms.is_empty() and player.solids.size() == base, "it breaks on time and stops being solid") and ok
	var fell := false
	for i in 60:
		await physics_frame
		if player.global_position.y > room.position.y + 150.0:
			fell = true
			break
	ok = _check(fell, "and the player falls") and ok

	# Longer, from the ability.
	state.abilities.imprint_duration = 6.0
	state.abilities.imprint_width = 3
	player.place(room.position + Grid.cell_center(Vector2i(20, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(5, 5)
	tool.place()
	ok = _check(is_equal_approx(tool.platforms[0].lifetime, 6.0) and is_equal_approx(tool.platforms[0].rect.size.x, 30.0), "width and duration come from the abilities") and ok
	state.abilities.imprint_duration = Abilities.new().imprint_duration
	state.abilities.imprint_width = Abilities.new().imprint_width

	# With the cooldown off, the next may go the moment one breaks.
	tool.clear(false)
	tool.sync_solids()
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(10, 14)
	tool.place()
	tool.platforms[0].lifetime = 0.05
	for i in 6:
		await physics_frame
	ok = _check(tool.platforms.is_empty() and is_zero_approx(tool.cooldown_left) and tool.place(), "with the cooldown off, another may go as soon as one has broken") and ok

	# With a cooldown, it starts when the platform breaks and refuses until it is over.
	state.abilities.imprint_cooldown = 0.2
	tool.clear(false)
	tool.sync_solids()
	tool.place()
	tool.platforms[0].lifetime = 0.3
	ok = _check(tool.cooldown_left == 0.0, "a cooldown does not run while the platform stands") and ok
	for i in 60:
		await physics_frame
		if tool.platforms.is_empty():
			break
	ok = _check(tool.platforms.is_empty() and tool.cooldown_left > 0.15 and tool.cooldown_left <= 0.2, "the cooldown starts, in full, when the platform breaks (%.3f)" % tool.cooldown_left) and ok
	ok = _check(not tool.place() and tool.platforms.is_empty(), "and a click in it does nothing") and ok
	tool.refresh_preview()
	ok = _check(tool.preview_state() == "unavailable" and tool.preview_reason() == "cooldown", "the cursor is the cross, for the cooldown (%s)" % tool.preview_reason()) and ok
	for i in 14:
		await physics_frame
	ok = _check(is_zero_approx(tool.cooldown_left) and tool.place(), "after about 0.2 s another may go") and ok
	tool.refresh_preview()
	ok = _check(tool.preview_reason() == "limit", "and the cooldown is not what refuses the next (%s)" % tool.preview_reason()) and ok

	# More at once is the upgrade's limit, still without replacing.
	state.abilities.imprint_cooldown = 0.0
	state.abilities.imprint_max_active = 2
	tool.clear(false)
	tool.sync_solids()
	tool.scripted_cell = Vector2i(10, 14)
	var two: bool = tool.place()
	tool.scripted_cell = Vector2i(14, 14)
	two = tool.place() and two
	tool.scripted_cell = Vector2i(18, 14)
	ok = _check(two and tool.platforms.size() == 2 and not tool.place() and tool.platforms.size() == 2, "at a limit of two, two stand and a third is refused") and ok
	state.abilities.imprint_max_active = 1

	# It shrinks: the default platform is three blocks, and a block goes every third of its life.
	state.abilities.imprint_cooldown = 0.2
	tool.clear(false)
	tool.sync_solids()
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(3, 6)
	ok = _check(tool.place() and tool.platforms[0].shrinks and is_equal_approx(tool.platforms[0].rect.size.x, 30.0), "the default platform is 30 px wide and shrinks") and ok
	player.global_position = room.position + Vector2(35.0, 20.0)
	player.velocity = Vector2.ZERO
	for i in 20:
		await physics_frame
	ok = _check(player.is_on_floor() and player.global_position.y < room.position.y + 60.0, "a player on the left block stands on it at first (%s)" % player.global_position) and ok
	var blocks: ImprintPlatform = tool.platforms[0]
	var solids := player.solids.size()
	for i in 60:
		await physics_frame
		if blocks.rect.size.x < 29.0:
			break
	ok = _check(is_equal_approx(blocks.rect.size.x, 20.0) and is_equal_approx(blocks.rect.position.x, room.position.x + 40.0), "the left block goes first (%s)" % [blocks.rect]) and ok
	ok = _check(player.solids.size() == solids and player.solids.has(blocks.rect), "the player's solids are the same count, and hold the smaller rect") and ok
	ok = _check(is_zero_approx(tool.cooldown_left) and tool.platforms.size() == 1, "a block going does not start the cooldown, and the platform stays") and ok
	var dropped := false
	for i in 40:
		await physics_frame
		if player.global_position.y > room.position.y + 80.0:
			dropped = true
			break
	ok = _check(dropped, "a player standing only on the left block falls when it goes") and ok
	for i in 90:
		await physics_frame
		if tool.platforms.is_empty():
			break
	ok = _check(tool.platforms.is_empty() and tool.cooldown_left > 0.1, "the cooldown starts when the platform finally breaks (%.3f)" % tool.cooldown_left) and ok

	# The middle block stands the whole life.
	tool.clear(false)
	tool.sync_solids()
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	ok = _check(tool.place(), "(another one goes)") and ok
	player.global_position = room.position + Vector2(45.0, 20.0)
	player.velocity = Vector2.ZERO
	for i in 20:
		await physics_frame
	blocks = tool.platforms[0]
	var stood := true
	for i in 70:
		await physics_frame
		if blocks.age > 1.3:
			break
		stood = stood and player.is_on_floor()
	ok = _check(stood and is_equal_approx(blocks.rect.size.x, 10.0), "a player on the middle block stands until the last moment (%s)" % [blocks.rect]) and ok
	tool.clear(false)
	tool.sync_solids()
	state.abilities.imprint_cooldown = 0.0

	# The cursor's refusal follows the footing: where a block has gone, a platform may go.
	state.abilities.imprint_max_active = 2
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(3, 6)
	tool.place()
	tool.scripted_cell = Vector2i(1, 6)
	tool.refresh_preview()
	ok = _check(tool.preview_reason() == "imprint", "a cursor over a standing platform is refused (%s)" % tool.preview_reason()) and ok
	for i in 60:
		await physics_frame
		if tool.platforms[0].rect.size.x < 29.0:
			break
	ok = _check(tool.preview_reason() == "" and tool.preview_state() != "unavailable", "and once its left block goes the same cursor is allowed, with no new click or move (%s)" % tool.preview_reason()) and ok
	state.abilities.imprint_max_active = 1
	tool.clear(false)
	tool.sync_solids()

	# Classic keeps its width, but only in a dev test.
	var session: Node = root.get_node("DevSession")
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	session.classic_imprint = true
	tool.scripted_cell = Vector2i(3, 6)
	ok = _check(tool.place() and tool.platforms[0].shrinks, "with the switch on outside a dev test, it shrinks anyway") and ok
	tool.clear(false)
	tool.sync_solids()
	session.mode = session.Mode.DEV_TEST
	ok = _check(tool.place() and not tool.platforms[0].shrinks and is_equal_approx(tool.platforms[0].rect.size.x, 30.0), "in a dev test with the switch on, it keeps its width") and ok
	tool.platforms[0].age = 1.0
	await physics_frame
	ok = _check(is_equal_approx(tool.platforms[0].rect.size.x, 30.0), "and keeps it late in its life") and ok
	session.mode = session.Mode.NORMAL
	session.classic_imprint = false
	tool.clear(false)
	tool.sync_solids()

	# Leaving the room clears it, and the cooldown with it.
	tool.cooldown_left = 5.0
	ok = _check(world.warp_to("4") and tool.platforms.is_empty() and world.get_node("Player").solids.size() == world.current.world_rects().size(), "leaving a room removes the platform and its collision") and ok
	ok = _check(is_zero_approx(tool.cooldown_left), "and ends the cooldown") and ok

	# Dying clears it.
	world.warp_to("5")
	room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	tool.scripted_cell = Vector2i(5, 8)
	tool.place()
	tool.cooldown_left = 5.0
	player.global_position = room.position + Vector2(160.0, 400.0)
	for i in 30:
		await physics_frame
	ok = _check(tool.platforms.is_empty(), "dying removes the platform") and ok
	ok = _check(is_zero_approx(tool.cooldown_left), "and the cooldown") and ok

	world.queue_free()
	await process_frame
	state.reset()
	print("IMPRINTPLAY %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
