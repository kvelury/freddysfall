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


## What is cut out of each picture for the tokens carried, and the Imprint line.
func _marks() -> bool:
	var ok := true
	var stand: FreddySprites.Frame = FreddySprites.animation(PlayerAnimator.Pose.STAND).frames[0]
	var land: FreddySprites.Frame = FreddySprites.animation(PlayerAnimator.Pose.LAND).frames[0]
	ok = _check(InventoryMarks.MAX_TOKENS == root.get_node("GameState").TOKEN_CAP, "the marks hold as many tokens as the pocket does") and ok
	var counts := []
	for tokens in 4:
		counts.append(InventoryMarks.pixels(stand, tokens, false).size())
	ok = _check(counts == [0, 2, 4, 6], "each token cuts a 2 x 1 line, two pixels, out of the body (%s)" % [counts]) and ok
	var line := InventoryMarks.pixels(stand, 0, true)
	var crowded := InventoryMarks.pixels(stand, 3, true)
	ok = _check(line.size() == 5, "the Imprint line is five pixels") and ok
	var overlap := 0
	for p in crowded:
		if crowded.count(p) > 1:
			overlap += 1
	ok = _check(crowded.size() == 11 and overlap == 0, "three tokens and the line never share a pixel (%d)" % crowded.size()) and ok
	var inside := true
	for p in crowded:
		inside = inside and p.x >= 0 and p.y >= 0 and p.x < FreddySprites.SIZE and p.y < FreddySprites.SIZE
	ok = _check(inside, "and all of them are inside the 10 x 10 body") and ok
	ok = _check(line.all(func(p: Vector2i) -> bool: return p.y == 7 and p.x >= 4 and p.x <= 8), "the line runs along row 7, from column 4 to 8") and ok
	ok = _check(InventoryMarks.pixels(stand, 7, false).size() == 6, "more than three tokens draws no more than three") and ok
	# Exact approved marks on the standing picture: two one pixel inside the rear
	# edge, bottom first, with one clear row between them, then the third in the
	# middle level with the gap, and the line clear of all three. Every count,
	# with and without Imprint.
	var slots := [Vector2i(1, 6), Vector2i(1, 4), Vector2i(4, 5)]
	for tokens in 5:
		for imprint in [false, true]:
			var expected: Array[Vector2i] = []
			for i in mini(tokens, 3):
				for dx in 2:
					expected.append(slots[i] + Vector2i(dx, 0))
			if imprint:
				for x in range(4, 9):
					expected.append(Vector2i(x, 7))
			var actual := InventoryMarks.pixels(stand, tokens, imprint)
			ok = _check(actual == expected, "the standing marks, in order: tokens %d, Imprint %s" % [tokens, imprint]) and ok
	# Landing is short: up to two token lines and never the line.
	var landing_ok := true
	for tokens in 5:
		for imprint in [false, true]:
			landing_ok = landing_ok and InventoryMarks.pixels(land, tokens, imprint).size() == 2 * mini(tokens, 2)
	ok = _check(landing_ok and land.line.is_empty(), "landing shows at most two token lines and never the Imprint line") and ok
	ok = _check(InventoryMarks.pixels(land, 3, true) == ([Vector2i(1, 8), Vector2i(2, 8), Vector2i(1, 6), Vector2i(2, 6)] as Array[Vector2i]), "and they are the two on the rows above the rear foot") and ok
	# What is drawn: the pupils and the cuts, facing either way, the left being
	# the right mirrored. Marks are cut before the picture is mirrored.
	var right := _black(FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 3, true))
	var left := _black(FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, -1, 3, true))
	var mirrored := left.map(func(p: Vector2i) -> Vector2i: return Vector2i(9 - p.x, p.y))
	ok = _check(_same(right, mirrored), "facing left draws the same marks mirrored") and ok
	var rear_right := crowded.filter(func(p: Vector2i) -> bool: return p.x <= 2)
	var rear_left := left.filter(func(p: Vector2i) -> bool: return p.x >= 7 and p.y >= 4)
	ok = _check(rear_right.size() == 4 and rear_left.size() == 4, "facing right the stack of two is at the left edge and facing left the right (%d, %d)" % [rear_right.size(), rear_left.size()]) and ok
	ok = _check(crowded.has(Vector2i(4, 5)) and crowded.has(Vector2i(5, 5)), "and the third token is in the middle of the body") and ok
	ok = _check(crowded.all(func(p: Vector2i) -> bool: return p.y >= 4), "and no mark is up by the eyes (all on row 4 or lower)") and ok
	# On every picture the player can show, with all the marks: each is cut from
	# the frog's lime body, and no black group (a token line, the Imprint line, a
	# pupil) touches another, even at a corner.
	var lands := true
	var touching := ""
	var drawn_ok := true
	for frame in FreddySprites.frames():
		for p in InventoryMarks.pixels(frame, 3, true):
			var y := p.y - frame.top
			lands = lands and y >= 0 and y < frame.rows.size() and frame.rows[y][p.x] == FreddySprites.BODY_PIXEL
		var groups: Array = []
		for i in mini(3, frame.tokens.size()):
			groups.append([frame.tokens[i], frame.tokens[i] + Vector2i(1, 0)])
		if not frame.line.is_empty():
			groups.append(frame.line)
		for y in frame.rows.size():
			for x in frame.rows[y].length():
				if frame.rows[y][x] == FreddySprites.MARK_PIXEL:
					groups.append([Vector2i(x, y + frame.top)])
		for i in groups.size():
			for j in range(i + 1, groups.size()):
				for a: Vector2i in groups[i]:
					for b: Vector2i in groups[j]:
						if absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1:
							touching = "%s: %s next to %s" % [frame.rows, a, b]
		var cells: Array[Vector2i] = []
		for g: Array in groups:
			cells.append_array(g)
		for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
			for i in FreddySprites.animation(pose).frames.size():
				if FreddySprites.animation(pose).frames[i] != frame:
					continue
				drawn_ok = drawn_ok and _same(_black(FreddySprites.rects(pose, i, 1, 3, true)), cells)
				drawn_ok = drawn_ok and _same(_black(FreddySprites.rects(pose, i, -1, 3, true)).map(func(p: Vector2i) -> Vector2i: return Vector2i(9 - p.x, p.y)), cells)
	ok = _check(lands, "every mark lands on the frog's lime body when it stands, walks, jumps or lands") and ok
	ok = _check(touching == "", "and no two marks touch, nor a mark and an eye, even at a corner, on any picture %s" % touching) and ok
	ok = _check(drawn_ok, "and what is drawn, facing either way, is the pupils and those marks and nothing else") and ok
	return ok


## The black cells of a drawn picture.
func _black(drawn: FreddySprites.Drawn) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for box in drawn.rects_in(Color.BLACK):
		for y in int(box.size.y):
			for x in int(box.size.x):
				out.append(Vector2i(int(box.position.x) + x, int(box.position.y) + y))
	return out


func _same(a: Array, b: Array) -> bool:
	return a.size() == b.size() and a.all(func(p: Variant) -> bool: return b.count(p) == 1)


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
