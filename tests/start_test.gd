extends SceneTree

## Starting in, and warping to, any room.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


# Nodes added in _initialize only get their _ready on the first frame, so each
# world is given one before it is looked at.
func _run() -> void:
	var ok := true
	ok = await _start("3", "3", "start_override puts the player in room 3") and ok
	ok = await _start("99", "s1", "an unknown room falls back to the start room") and ok
	ok = await _start("", "s1", "no request starts in the start room") and ok

	var world: Node = await _world("s1")
	ok = _check(world.warp_to("2") and _in(world, "2"), "warp_to moves the player to room 2") and ok
	ok = _check(not world.warp_to("99") and _in(world, "2"), "warp_to refuses an unknown room and stays put") and ok
	ok = _check(world.warp_to("3") and _stands(world), "after a warp the player is standing on floor") and ok
	var overlay := world.get_node("DebugOverlay")
	_press(overlay, KEY_F4)
	_press(overlay, KEY_3, 51)
	_press(overlay, KEY_ENTER)
	ok = _check(_in(world, "3"), "F4, 3, Enter warps to room 3") and ok
	_press(overlay, KEY_F4)
	_press(overlay, KEY_9, 57)
	_press(overlay, KEY_ENTER)
	ok = _check(_in(world, "3"), "F4, 9, Enter stays put when there is no room 9") and ok
	_press(overlay, KEY_ESCAPE)
	_press(overlay, KEY_2, 50)
	_press(overlay, KEY_ENTER)
	ok = _check(_in(world, "3"), "keys typed after Escape do nothing") and ok
	_press(overlay, KEY_F4)
	_press(overlay, KEY_S, 115)
	_press(overlay, KEY_1, 49)
	_press(overlay, KEY_ENTER)
	ok = _check(_in(world, "s1"), "F4, s, 1, Enter warps to save room s1") and ok
	print("START %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _world(override: String) -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = override
	root.add_child(world)
	await process_frame
	return world


func _start(override: String, expected: String, label: String) -> bool:
	var world: Node = await _world(override)
	var ok := _check(_in(world, expected) and _stands(world), label)
	world.free()
	return ok


func _in(world: Node, id: String) -> bool:
	var info: RoomInfo = root.get_node("WorldData").get_room(id)
	var area := Rect2(Vector2(info.grid_pos) * Grid.SCREEN_SIZE, info.pixel_size)
	var player: Player = world.get_node("Player")
	return _room_id() == id and area.has_point(player.global_position)


## The cell under the player's feet is solid and the cell they occupy is not.
func _stands(world: Node) -> bool:
	var player: Player = world.get_node("Player")
	var info: RoomInfo = root.get_node("WorldData").get_room(_room_id())
	var cell := Grid.world_to_cell(player.global_position - Vector2(info.grid_pos) * Grid.SCREEN_SIZE)
	return not info.is_solid(cell.x, cell.y) and info.is_solid(cell.x, cell.y + 1)


func _press(overlay: Node, keycode: Key, unicode := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.unicode = unicode
	event.pressed = true
	overlay._unhandled_input(event)


func _room_id() -> String:
	return String(root.get_node("GameState").current_room_id)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
