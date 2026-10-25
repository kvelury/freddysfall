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
	var panel := world.get_node("DevPanel")
	_press(panel, KEY_F4)
	ok = _check(panel.opened and panel._tabs.current_tab == 1 and root.get_node("DevSession").isolated(), "F4 opens the isolated room picker") and ok
	panel._room.text = "99"
	panel._start(false)
	ok = _check(_in(world, "3") and "No such room" in panel._status.text, "unknown room stays put with an error") and ok
	_press(panel, KEY_ESCAPE)
	ok = _check(not panel.opened and not paused, "Escape cancels room selection and releases pause") and ok
	world.free()
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
	overlay._input(event)


func _room_id() -> String:
	return String(root.get_node("GameState").current_room_id)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
