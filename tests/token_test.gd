extends SceneTree

## Room 2 holds its doors shut behind blocks until its token is taken. Taking it
## opens them, the player carries it (shown on their body), a full pocket leaves
## the next token where it is, and the game saves and resumes with the token
## spent and the doors open.

const TEMP := "user://token_test.json"


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := _marks()
	var state: Node = root.get_node("GameState")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = true
	DirAccess.remove_absolute(TEMP)
	state.reset()

	var world: Node = await _world()
	ok = _check(world.warp_to("2"), "warp to room 2, which has the token") and ok
	var player: Player = world.get_node("Player")
	player.scripted = true
	var room: Room = world.current
	ok = _check(room.locked, "room 2 starts with its doors blocked") and ok
	ok = _check(_count(room, "DoorBlock") == 3 and _count(room, "ExitHalo") == 0, "three blocks fill its three doorways, and no halo shows (%d blocks, %d halos)" % [_count(room, "DoorBlock"), _count(room, "ExitHalo")]) and ok
	ok = _check(room.world_rects().size() == room.info.solids.size() + 3, "the blocks are solid") and ok
	ok = _check(_things(room, "Token").size() == 1, "room 2 shows its token") and ok
	ok = _check(not state.abilities.imprint_unlocked and state.tokens == 0, "the player starts with nothing") and ok

	# Walk left into the blocked door on the player's own platform.
	player.place(room.position + Grid.cell_center(Vector2i(3, 4)), room.world_rects())
	player.scripted_x = -1.0
	await _frames(90)
	player.scripted_x = 0.0
	ok = _check(world.current.info.id == "2", "walking into a blocked door does not leave the room") and ok
	ok = _check(player.global_position.x - room.position.x > 14.0, "the block stops the player at the wall (x %s)" % (player.global_position.x - room.position.x)) and ok

	# Take the token, from the platform it sits beside.
	var opened := [false]
	room.exits_opened.connect(func() -> void: opened[0] = true)
	var rects_before := player.solids.size()
	player.place(room.position + Grid.cell_center(Vector2i(8, 8)), room.world_rects())
	player.scripted_x = 1.0
	for i in 120:
		await physics_frame
		if state.has_flag("token:r2_token"):
			break
	player.scripted_x = 0.0
	await _frames(3)
	ok = _check(state.tokens == 1 and state.has_flag("token:r2_token"), "walking into the token takes it") and ok
	ok = _check(opened[0] and not room.locked, "and the room's doors open") and ok
	ok = _check(_count(room, "DoorBlock") == 0 and _count(room, "ExitHalo") == 3, "the blocks are gone and the halos are there (%d blocks, %d halos)" % [_count(room, "DoorBlock"), _count(room, "ExitHalo")]) and ok
	ok = _check(player.solids.size() == rects_before - 3, "and the player no longer collides with them (%d to %d)" % [rects_before, player.solids.size()]) and ok
	ok = _check(_things(room, "Token").is_empty(), "the token is gone from the room") and ok
	ok = _check(FileAccess.file_exists(TEMP), "and the game saved") and ok
	ok = _check(not state.abilities.imprint_unlocked, "the token alone gives no Imprint") and ok

	# Out the left door now.
	player.place(room.position + Grid.cell_center(Vector2i(3, 4)), room.world_rects())
	player.scripted_x = -1.0
	for i in 240:
		await physics_frame
		if world.current.info.id == "s1" and player.input_enabled:
			break
	player.scripted_x = 0.0
	ok = _check(world.current.info.id == "s1", "the door works now, into room s1") and ok

	# A full pocket leaves the next token where it is.
	world.warp_to("3")
	room = world.current
	state.tokens = state.TOKEN_CAP
	state.tokens_changed.emit()
	player.place(room.position + Grid.cell_center(Vector2i(18, 4)), room.world_rects())
	await _frames(10)
	ok = _check(state.tokens == 3 and not state.has_flag("token:r3_token") and _things(room, "Token").size() == 1, "a token touched with three already carried stays on the platform") and ok
	ok = _check(not world.get_node("Toast").get_child(0).visible, "and it says nothing") and ok
	state.tokens = 1
	state.tokens_changed.emit()
	await _frames(20)
	ok = _check(state.tokens == 2 and state.has_flag("token:r3_token"), "once there is room it is taken the next time it is touched (%d)" % state.tokens) and ok

	# A fresh game from the save: in room 3 with the token spent.
	world.queue_free()
	await process_frame
	state.reset()
	world = await _world()
	room = world.current
	ok = _check(room.info.id == "s1", "starting again resumes at the save room, not where the player was (%s)" % room.info.id) and ok
	# The resume point is inside the save machine, which lets the player out first.
	while world.is_busy():
		await physics_frame
	ok = _check(state.has_flag("token:r2_token") and state.tokens == 2, "with the token flags and the two carried (%d)" % state.tokens) and ok
	ok = _check(world.warp_to("2") and world.current.info.id == "2" and not world.current.locked and _count(world.current, "DoorBlock") == 0, "and room 2 comes up with its doors open") and ok

	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	print("TOKEN %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## What is cut out of the body for the tokens carried, and the Imprint line.
func _marks() -> bool:
	var ok := true
	var counts := []
	for tokens in 4:
		counts.append(InventoryMarks.pixels(tokens, false).size())
	ok = _check(counts == [0, 2, 4, 6], "each token cuts a 2 x 1 line, two pixels, out of the body (%s)" % [counts]) and ok
	ok = _check(InventoryMarks.pixels(0, true).size() == 8, "the Imprint line is eight pixels") and ok
	var line := InventoryMarks.pixels(0, true)
	var crowded := InventoryMarks.pixels(3, true)
	var overlap := 0
	for p in crowded:
		if crowded.count(p) > 1:
			overlap += 1
	ok = _check(crowded.size() == 14 and overlap == 0, "three tokens and the line never share a pixel (%d)" % crowded.size()) and ok
	var inside := true
	for p in crowded:
		inside = inside and p.x >= 0 and p.y >= 0 and p.x < 10 and p.y < 10
	ok = _check(inside, "and all of them are inside the 10 x 10 body") and ok
	ok = _check(line.all(func(p: Vector2i) -> bool: return p.y == 8), "the line runs along the one row") and ok
	ok = _check(InventoryMarks.pixels(7, false).size() == 6, "more than three tokens draws no more than three") and ok
	# Exact approved stack: one pixel inside the rear edge, bottom first,
	# with one clear row between marks. Test every count with and without Imprint.
	var slots := [Vector2i(1, 6), Vector2i(1, 4), Vector2i(1, 2)]
	for face in [0, 1, -1]:
		for tokens in 4:
			for imprint in [false, true]:
				var expected: Array[Vector2i] = []
				for i in tokens:
					for dx in 2:
						var p: Vector2i = slots[i] + Vector2i(dx, 0)
						expected.append(Vector2i(9 - p.x, p.y) if face < 0 else p)
				if imprint:
					for x in range(1, 9):
						expected.append(Vector2i(x, 8))
				if face != 0:
					expected.append_array(InventoryMarks.FACE_RIGHT if face > 0 else InventoryMarks.FACE_LEFT)
				var actual := InventoryMarks.pixels(tokens, imprint, face)
				ok = _check(actual.size() == expected.size() and expected.all(func(p: Vector2i) -> bool: return actual.count(p) == 1), "rear stack fills bottom to top with padding: face %d, tokens %d, Imprint %s" % [face, tokens, imprint]) and ok
	# The facing block: 2 x 2, one row down in the top right when facing right, the top left when facing left.
	var right := InventoryMarks.pixels(3, true, 1)
	var left := InventoryMarks.pixels(3, true, -1)
	var clear := true
	for p in InventoryMarks.FACE_RIGHT + InventoryMarks.FACE_LEFT:
		clear = clear and p.x >= 0 and p.y >= 0 and p.x < 10 and p.y < 10
	for marks in [right, left]:
		for p in marks:
			clear = clear and marks.count(p) == 1
	ok = _check(clear and right.size() == 18 and left.size() == 18, "the facing block adds four pixels inside the body, on none of the other marks") and ok
	ok = _check(InventoryMarks.FACE_RIGHT.all(func(p: Vector2i) -> bool: return p.x >= 8 and p.y in [1, 2]) and InventoryMarks.FACE_RIGHT.size() == 4, "facing right it is the 2 x 2 block in the top right") and ok
	ok = _check(InventoryMarks.FACE_LEFT.all(func(p: Vector2i) -> bool: return p.x <= 1 and p.y in [1, 2]) and InventoryMarks.FACE_LEFT.size() == 4, "facing left it is the 2 x 2 block in the top left") and ok
	ok = _check(InventoryMarks.FACE_LEFT.all(func(p: Vector2i) -> bool: return InventoryMarks.FACE_RIGHT.has(Vector2i(9 - p.x, p.y))), "and the two are mirror images") and ok
	ok = _check(InventoryMarks.pixels(0, false, 0).is_empty(), "no facing given draws no block") and ok
	return ok


func _count(room: Room, type: String) -> int:
	var found := 0
	for child in room.get_children():
		if child.is_queued_for_deletion():
			continue
		if (type == "DoorBlock" and child is Room.DoorBlock) or (type == "ExitHalo" and child is ExitHalo):
			found += 1
	return found


func _things(room: Room, type: String) -> Array[Node]:
	return room.get_children().filter(func(c: Node) -> bool: return c.get_script() != null and String(c.get_script().get_global_name()) == type and not c.is_queued_for_deletion())


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _world() -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	return world


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
