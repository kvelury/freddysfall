extends SceneTree

## Spikes and falling out of the world put the player back on the last safe
## floor, after a short shatter.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "5"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	var ok := true

	# Room 5 has spikes in the floor at columns 10 to 13. Walk into them.
	player.place(room.position + Grid.cell_center(Vector2i(2, 16)), room.world_rects())
	player.scripted_x = 1.0
	var died := false
	for i in 240:
		await physics_frame
		if not player.visible:
			died = true
			break
	ok = _check(died, "walking into spikes kills the player") and ok
	ok = _check(not player.input_enabled, "control is taken while the shards fly") and ok
	var shards := 0
	for child in world.get_children():
		if child is Shatter:
			shards += 1
	ok = _check(shards == 1, "a shatter plays (%d)" % shards) and ok
	player.scripted_x = 0.0
	ok = _check(await _respawned(player), "the player comes back") and ok
	ok = _check(_standing_left_of_spikes(world, player), "they come back standing on the safe floor left of the spikes (%s)" % player.global_position) and ok

	# Out of the world: dropped far below the room. Respawning built a new room.
	room = world.current
	player.place(room.position + Vector2(160.0, 400.0), room.world_rects())
	var fell := false
	for i in 120:
		await physics_frame
		if not player.visible:
			fell = true
			break
	ok = _check(fell, "falling out of the room kills the player") and ok
	ok = _check(await _respawned(player), "the player comes back from the fall") and ok
	room = world.current
	var bounds := Rect2(room.position, Vector2(320, 180))
	ok = _check(bounds.has_point(player.global_position), "and is back inside the room (%s)" % player.global_position) and ok
	ok = await _imprint_loop(world, player) and ok
	print("HAZARD %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## An Imprint over spikes breaks under the player. They must come back on the
## room's own floor, not in the air where it was, and a bad spot is stepped back
## from.
func _imprint_loop(world: Node, player: Player) -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	var tool: Node = world.get_node("Imprint")
	state.abilities.imprint_unlocked = true
	tool.scripted = true
	var room: Room = world.current
	var floor_spot := room.position + Grid.cell_center(Vector2i(6, 16))
	player.place(floor_spot, room.world_rects())
	for i in 10:
		await physics_frame

	tool.scripted_cell = Vector2i(11, 15)
	ok = _check(tool.place(), "an Imprint goes in just above the spikes") and ok
	player.global_position = room.position + Vector2(120.0, 145.0)
	player.velocity = Vector2.ZERO
	for i in 15:
		await physics_frame
	ok = _check(player.is_on_floor() and player.global_position.y < room.position.y + 150.0, "the player stands on it (%s)" % player.global_position) and ok
	ok = _check(world._safe[-1]["position"].distance_to(floor_spot) < 1.0, "but the safe spot is still the real floor (%s)" % world._safe[-1]["position"]) and ok

	tool.platforms[0].lifetime = 0.05
	var deaths := await _count_deaths(player, 400)
	ok = _check(deaths == 1, "it breaks, the player drops onto the spikes and dies once (%d)" % deaths) and ok
	room = world.current
	var local := player.global_position - room.position
	ok = _check(player.visible and player.is_on_floor() and local.x < 100.0 and absf(local.y - 165.0) < 0.6, "and comes back on the floor left of the spikes (%s)" % local) and ok

	# A spot that was never real: in the air over the spikes.
	world._record_safe(room.info.id, room.position + Vector2(120.0, 145.0))
	player.global_position = room.position + Vector2(120.0, 165.0)
	deaths = await _count_deaths(player, 600)
	ok = _check(deaths == 2, "a bad spot kills once more and then it is given up (%d deaths)" % deaths) and ok
	room = world.current
	local = player.global_position - room.position
	ok = _check(player.visible and player.is_on_floor() and local.x < 100.0 and absf(local.y - 165.0) < 0.6, "and the player is back on the floor they really stood on (%s)" % local) and ok
	state.abilities.imprint_unlocked = false
	return ok


## Counts the times the player dies over `frames` ticks, then waits for them to
## be back and standing.
func _count_deaths(player: Player, frames: int) -> int:
	var deaths := 0
	var was_alive := true
	for i in frames:
		await physics_frame
		if was_alive and not player.visible:
			deaths += 1
		was_alive = player.visible
	return deaths


func _respawned(player: Player) -> bool:
	for i in 180:
		await physics_frame
		if player.visible and player.input_enabled:
			for j in 30:
				await physics_frame
			return true
	return false


func _standing_left_of_spikes(world: Node, player: Player) -> bool:
	var room: Room = world.current
	var local := player.global_position - room.position
	return player.is_on_floor() and local.x > 10.0 and local.x < 100.0 and not room.touches_hazard(player.body_rect())


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
