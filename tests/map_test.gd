extends SceneTree

## The map's three zoom levels, the legend, and the level being part of the
## saved game. A new game wipes the save and the level with it, and a reload
## keeps both.

const TEMP := "user://map_test.json"
const VIEW := Vector2(240, 132)
## What MapLayer uses: a screen is 32 x 18 map units, set 40 x 26 apart.
const ROOM_PX := Vector2(32, 18)
const STRIDE := Vector2(40, 26)


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := _view()
	ok = _legend() and ok
	ok = await _overlay() and ok
	ok = await _new_game() and ok
	ok = await _no_jump() and ok
	ok = await _marker_in_room() and ok
	print("MAP %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## The numbers: the scale for each level, how rooms land when scaled, and where
## the window looks.
func _view() -> bool:
	var ok := true
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var world := Rect2()
	var first := true
	for info: RoomInfo in data.rooms.values():
		var rect := Rect2(Vector2(info.grid_pos) * STRIDE, Vector2(info.screens) * STRIDE - (STRIDE - ROOM_PX))
		world = rect if first else world.merge(rect)
		first = false
	world = world.grow(4.0)
	ok = _check(world.size.y * 1.0 > VIEW.y, "the whole world is taller than the window, which is why the map was cut off (%s)" % world.size) and ok

	var out := MapView.scale_for(MapView.OUT, world, VIEW)
	ok = _check(out < 1.0 and world.size.x * out <= VIEW.x and world.size.y * out <= VIEW.y, "zoomed out shows the whole map (scale %.3f)" % out) and ok
	ok = _check(MapView.scale_for(MapView.MIDDLE, world, VIEW) == 1.0, "the middle level is the old view") and ok
	ok = _check(MapView.scale_for(MapView.IN, world, VIEW) == 2.0, "zoomed in is twice that") and ok
	var one := Rect2(Vector2.ZERO, ROOM_PX).grow(4.0)
	ok = _check(MapView.scale_for(MapView.OUT, one, VIEW) == 1.0, "a small map is not blown up by zooming out") and ok
	var huge := Rect2(0, 0, 4000, 3000)
	var huge_scale := MapView.scale_for(MapView.OUT, huge, VIEW)
	ok = _check(huge.size.x * huge_scale <= VIEW.x + 0.01 and huge.size.y * huge_scale <= VIEW.y + 0.01, "however big the map gets, zoomed out still shows all of it (scale %.3f)" % huge_scale) and ok

	var steps := [MapView.step(1, 1), MapView.step(2, 1), MapView.step(1, -1), MapView.step(0, -1)]
	ok = _check(steps == [2, 2, 0, 0], "up and down move one level and stop at the ends (%s)" % [steps]) and ok
	ok = _check(MapView.clamp_level(9) == 2 and MapView.clamp_level(-3) == 0, "a level outside the range is brought back in") and ok
	ok = _check(_keys("map_zoom_in") == [KEY_UP, KEY_W] and _keys("map_zoom_out") == [KEY_DOWN, KEY_S], "Up or W zooms in, Down or S zooms out (%s, %s)" % [_keys("map_zoom_in"), _keys("map_zoom_out")]) and ok

	# Rooms that touch still touch and rooms with a gap keep one, at any scale.
	var apart := true
	var gap := Rect2(Vector2.ZERO, ROOM_PX)
	var next := Rect2(Vector2(STRIDE.x, 0), ROOM_PX)
	var stacked := Rect2(Vector2(0, STRIDE.y), ROOM_PX)
	for hundredths in range(30, 201, 7):
		var s := float(hundredths) / 100.0
		var a := MapView.scaled_rect(gap, s)
		apart = apart and MapView.scaled_rect(next, s).position.x > a.end.x and MapView.scaled_rect(stacked, s).position.y > a.end.y
	ok = _check(apart, "scaled rooms never touch or overlap their neighbours") and ok
	var joined := MapView.scaled_rect(Rect2(0, 0, 32, 18), 0.846)
	var joined_next := MapView.scaled_rect(Rect2(32, 0, 32, 18), 0.846)
	ok = _check(joined.end.x == joined_next.position.x and joined == joined.abs(), "two rooms that share an edge still share it when scaled") and ok
	ok = _check(MapView.scaled_rect(Rect2(10, 10, 32, 18), 2.0) == Rect2(20, 20, 64, 36), "zoomed in doubles a room") and ok

	# Where the window looks.
	var fits := MapView.view_center(Vector2(60, 40), one, 1.0, VIEW)
	ok = _check(fits == Vector2(60, 40), "a map that fits the window is looked at where it was asked") and ok
	var wide := world.grow(40.0)
	var corner := MapView.view_center(Vector2(-9999, -9999), wide, 2.0, VIEW)
	ok = _check(corner == (wide.position * 2.0 + VIEW * 0.5).round(), "zoomed in on the corner of a big map, the window stays on the map (%s)" % corner) and ok
	var far := MapView.view_center(Vector2(9999, 9999), wide, 2.0, VIEW)
	ok = _check(far == (wide.end * 2.0 - VIEW * 0.5).round(), "and at the far corner too (%s)" % far) and ok
	var odd := MapView.view_center(Vector2(31.3, 17.7), wide, 2.0, VIEW)
	ok = _check(odd == odd.round(), "the window sits on a whole pixel") and ok
	return ok


## The legend: a patch in the bottom-right corner, with both rows inside it,
## the row that can do nothing more in grey, and no pixel drawn twice.
func _legend() -> bool:
	var ok := true
	for level in 3:
		var pieces := MapView.legend(level, VIEW)
		var patch: Rect2i = pieces["patch"]
		var white: Array = pieces["white"]
		var grey: Array = pieces["grey"]
		ok = _check(Rect2i(Vector2i.ZERO, Vector2i(VIEW)).encloses(patch) and VIEW.x - patch.end.x <= 2 and VIEW.y - patch.end.y <= 2, "level %d: the legend is a patch in the bottom-right corner %s" % [level, patch]) and ok
		var all: Array = white + grey
		var inside := true
		for pixel: Vector2i in all:
			inside = inside and patch.has_point(pixel)
		ok = _check(inside, "level %d: every pixel is on the patch" % level) and ok
		var distinct := {}
		for pixel: Vector2i in all:
			distinct[pixel] = true
		ok = _check(distinct.size() == all.size(), "level %d: nothing is drawn twice, so the two rows do not overlap" % level) and ok
		var top_half := 0
		var bottom_half := 0
		var middle := patch.position.y + patch.size.y / 2
		for pixel: Vector2i in grey:
			if pixel.y < middle:
				top_half += 1
			else:
				bottom_half += 1
		var expect_top := level == MapView.IN
		var expect_bottom := level == MapView.OUT
		ok = _check((top_half > 0) == expect_top and (bottom_half > 0) == expect_bottom, "level %d: the plus is grey only when fully in, the minus only when fully out (%d, %d)" % [level, top_half, bottom_half]) and ok
	var pieces := MapView.legend(MapView.MIDDLE, VIEW)
	ok = _check(pieces["grey"].is_empty() and pieces["white"].size() > 30, "in the middle, both rows are white (%d pixels)" % pieces["white"].size()) and ok
	# The plus has two more pixels than the minus has, so the rows differ.
	var plus := 0
	var minus := 0
	var patch: Rect2i = pieces["patch"]
	for pixel: Vector2i in pieces["white"]:
		if pixel.y < patch.position.y + patch.size.y / 2:
			plus += 1
		else:
			minus += 1
	ok = _check(plus == minus + 2, "a plus has two pixels more than a minus, an up arrow as many as a down (%d, %d)" % [plus, minus]) and ok
	return ok


## The real overlay: the keys step the level and keep it in the game's state,
## and closing the map after a change saves.
func _overlay() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	state.current_room_id = "s1"
	for id in ["s1", "2", "3", "4", "5", "6", "7"]:
		state.visited[id] = true

	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar saves := 0\nfunc save_now() -> void:\n\tsaves += 1\n"
	stub.reload()
	var parent := Node.new()
	parent.set_script(stub)
	root.add_child(parent)
	var overlay: Node = (load("res://src/ui/map_overlay.tscn") as PackedScene).instantiate()
	parent.add_child(overlay)
	await process_frame
	ok = _check(state.map_zoom == MapView.MIDDLE and is_equal_approx(overlay.zoom, 1.0), "the map opens at the middle level") and ok

	Input.action_press("map")
	await process_frame
	await process_frame
	Input.action_press("map_zoom_out")
	await process_frame
	Input.action_release("map_zoom_out")
	await process_frame
	ok = _check(state.map_zoom == MapView.OUT and overlay.zoom < 1.0, "Down zooms out (level %d, scale %.2f)" % [state.map_zoom, overlay.zoom]) and ok
	Input.action_press("map_zoom_out")
	await process_frame
	Input.action_release("map_zoom_out")
	await process_frame
	ok = _check(state.map_zoom == MapView.OUT, "and stops there") and ok
	Input.action_press("map_zoom_in")
	await process_frame
	Input.action_release("map_zoom_in")
	await process_frame
	Input.action_press("map_zoom_in")
	await process_frame
	Input.action_release("map_zoom_in")
	await process_frame
	ok = _check(state.map_zoom == MapView.IN and is_equal_approx(overlay.zoom, 2.0), "Up twice zooms in (level %d, scale %.2f)" % [state.map_zoom, overlay.zoom]) and ok
	Input.action_press("map_zoom_in")
	await process_frame
	Input.action_release("map_zoom_in")
	await process_frame
	ok = _check(state.map_zoom == MapView.IN, "and stops there") and ok
	ok = _check(parent.saves == 0, "nothing is saved while the map is open") and ok
	Input.action_release("map")
	await process_frame
	await process_frame
	ok = _check(parent.saves == 1, "closing the map after a change saves the game (%d)" % parent.saves) and ok

	Input.action_press("map")
	await process_frame
	await process_frame
	Input.action_release("map")
	await process_frame
	await process_frame
	ok = _check(parent.saves == 1 and state.map_zoom == MapView.IN, "opening and closing without a change saves nothing, and keeps the level") and ok

	# The level is in what a save holds, and comes back from it.
	var held: Dictionary = state.to_dict()
	state.reset()
	ok = _check(state.map_zoom == MapView.MIDDLE, "resetting the game puts the map back at the middle") and ok
	state.load_dict(held)
	ok = _check(state.map_zoom == MapView.IN, "a saved game brings the level back") and ok
	state.load_dict({"map_zoom": 9})
	ok = _check(state.map_zoom == MapView.IN, "a level out of range in a save is brought back in range") and ok
	state.load_dict({"visited": ["s1"]})
	ok = _check(state.map_zoom == MapView.MIDDLE, "a save from before the zoom existed opens at the middle") and ok

	parent.queue_free()
	await process_frame
	state.reset()
	return ok


## A new game wipes the save, and the level with it. A reload keeps both.
func _new_game() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = true
	DirAccess.remove_absolute(TEMP)
	state.reset()
	state.visit("s1")
	state.visit("2")
	state.map_zoom = MapView.OUT
	ok = _check(save.write("2", Vector2(100, 100)), "a game is saved with the map zoomed out") and ok

	# A reload: the save and the level come back.
	state.reset()
	var world: Node = await _world(false)
	ok = _check(world.current.info.id == "2" and state.map_zoom == MapView.OUT, "a reload keeps the game and the zoom (room %s, level %d)" % [world.current.info.id, state.map_zoom]) and ok
	ok = _check(FileAccess.file_exists(TEMP), "and the save is still there") and ok
	world.queue_free()
	await process_frame

	# A new game: the file goes at once, before anything is autosaved.
	world = await _world(true)
	ok = _check(not FileAccess.file_exists(TEMP), "a new game deletes the save straight away") and ok
	ok = _check(world.current.info.id == "s1" and state.map_zoom == MapView.MIDDLE and state.visited.size() == 1, "it starts in room s1 with nothing visited, the map at the middle (%s, level %d, %d visited)" % [world.current.info.id, state.map_zoom, state.visited.size()]) and ok
	world.queue_free()
	await process_frame

	# So a reload after that has nothing to bring back.
	world = await _world(false)
	ok = _check(world.current.info.id == "s1" and state.map_zoom == MapView.MIDDLE, "reloading right after a new game cannot bring the old game back") and ok
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEMP)
	save.enabled = false
	state.reset()
	return ok


## Up is also jump. Pressing it while the map is open must not make the player
## jump when the map closes.
func _no_jump() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	var world: Node = await _world(true)
	var player: Player = world.get_node("Player")
	for i in 60:
		await physics_frame
	var floor_y := player.global_position.y
	ok = _check(player.is_on_floor(), "the player stands on the floor to begin with") and ok
	Input.action_press("map")
	for i in 5:
		await physics_frame
	Input.action_press("jump")
	Input.action_press("map_zoom_in")
	for i in 5:
		await process_frame
	Input.action_release("jump")
	Input.action_release("map_zoom_in")
	Input.action_release("map")
	var rose := 0.0
	for i in 60:
		await physics_frame
		rose = maxf(rose, floor_y - player.global_position.y)
	ok = _check(rose < 1.0, "pressing Up while the map is open does not jump the player after (rose %.1f px)" % rose) and ok
	world.queue_free()
	await process_frame
	state.reset()
	return ok


## Where the room layer is drawn from, in window pixels: what the viewport
## will render with on the very next frame.
func _drawn_offset(overlay: Node) -> Vector2:
	var viewport: SubViewport = overlay._viewport
	var layer: Node2D = overlay._layer
	return (viewport.canvas_transform * layer.get_transform()).origin


## The map and the marker are drawn from the same place, at once, at every
## level. The room layer's picture is rendered once, right after a change, so
## it must already be where the marker will be, and not a step behind.
func _marker_in_room() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	var world: Node = await _world(true)
	for id in ["s1", "2", "3", "4", "5", "6", "7"]:
		state.visited[id] = true
	world.warp_to("7")
	var player: Player = world.get_node("Player")
	var room: Room = world.current
	var overlay: Node = world.get_node("MapOverlay")
	var layer_class = overlay.get_script().get_script_constant_map()["MapLayer"]
	var info: RoomInfo = room.info
	var window := Rect2(Vector2.ZERO, VIEW)
	var names := ["Out", "Middle", "In"]
	# With physics interpolation on, a node moved between physics steps is drawn
	# part of the way from where it was. The layer has to jump, not glide.
	ok = _check(overlay._layer.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "the map's layer is not interpolated, so it is drawn where it was put") and ok
	for level in 3:
		overlay.set_level(level)
		var expected: Vector2 = VIEW * 0.5 - overlay.view_center
		var drawn := _drawn_offset(overlay)
		ok = _check(drawn == expected, "%s: the map is drawn from where the marker thinks it is, with no frame in between (%s, expected %s)" % [names[level], drawn, expected]) and ok
		for cell in [Vector2i(3, 70), Vector2i(28, 70), Vector2i(3, 3), Vector2i(28, 3), Vector2i(16, 35)]:
			player.place(room.position + Grid.cell_center(cell), room.world_rects())
			overlay.refresh()
			var box := MapView.scaled_rect(layer_class.room_rect(info), overlay.zoom)
			box.position += _drawn_offset(overlay)
			var marker: Vector2 = overlay.marker_position()
			ok = _check(box.grow(1.0).has_point(marker) and window.has_point(marker), "%s: the marker for cell %s is inside room 7 and the window (marker %s, room %s)" % [names[level], cell, marker, box]) and ok
		if level == MapView.OUT:
			overlay.refresh()
			var all_in := true
			for id in state.visited.keys():
				var other: RoomInfo = root.get_node("WorldData").rooms.get(id)
				var other_box := MapView.scaled_rect(layer_class.room_rect(other), overlay.zoom)
				other_box.position += _drawn_offset(overlay)
				all_in = all_in and window.encloses(other_box)
			ok = _check(all_in, "Out: every visited room is inside the window") and ok
	world.queue_free()
	await process_frame
	state.reset()
	return ok


func _world(new_game: bool) -> Node:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.new_game = new_game
	root.add_child(world)
	await process_frame
	return world


## The physical keys bound to an action, in order.
func _keys(action: String) -> Array:
	var out := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append((event as InputEventKey).physical_keycode)
	return out


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
