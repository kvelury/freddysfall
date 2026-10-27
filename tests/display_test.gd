extends SceneTree

## The picture is drawn at 640 x 360, two screen pixels to a world pixel, and
## the world stays on whole world pixels: the project and camera settings, the
## snapping rule, the pixel pictures that replaced the polygons, the player's
## body and marks, the moving platform and the UI scale. The renderer-side check
## (every frame on the grid, equal to the 320 x 180 baseline) is
## tools/pixel_check.sh.

var _ok := true


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	_settings()
	_snapping()
	_pictures()
	_body()
	await _world()
	print("DISPLAY %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


func _settings() -> void:
	var size := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	_check(size == Display.VIEWPORT and Vector2(size) == Grid.SCREEN_SIZE * float(Display.RENDER_SCALE), "the viewport is the screen size times the render scale (%s)" % size)
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "it still stretches as the viewport, by whole numbers, keeping the aspect")
	_check(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0, "and still filters nearest")
	_check(ProjectSettings.get_setting("display/window/size/window_width_override") == Display.VIEWPORT.x * 2, "the default window is twice the viewport")


func _snapping() -> void:
	var table := {-1.5: -2.0, -0.51: -1.0, -0.5: -1.0, 0.0: 0.0, 0.49: 0.0, 0.5: 0.0, 0.51: 1.0, 2.5: 2.0, 2.51: 3.0, 9.5: 9.0, 100.0: 100.0}
	for value in table:
		_check(Display.snapf(value) == table[value], "x = %s lights pixel %s" % [value, table[value]])
	_check(Display.snap(Vector2(3.5, 4.51)) == Vector2(3, 5), "a point snaps each axis")
	# A squashed body at 0.9 x 1.1 on a whole centre: 9 wide, 11 tall.
	_check(Display.snap_rect(Rect2(20.5, 159.5, 9.0, 11.0)) == Rect2(20, 159, 9, 11), "a rect keeps the pixels whose centres it covers")
	_check(Display.snap_rect(Rect2(10.0, 10.0, 10.0, 1.0)) == Rect2(10, 10, 10, 1), "a rect on whole pixels is unchanged")
	# A 1 x 1 box centred on p is the pixel snap(p - 0.5), which is what a dust speck lights.
	_check(Display.snap_rect(Rect2(10.0 - 0.5, 20.0 - 0.5, 1.0, 1.0)) == Rect2(9, 19, 1, 1), "a speck centred on a whole pixel lights the one above and left")
	# The rule is additive in whole pixels, so moving a node by whole pixels never changes what it lights.
	var worst := 0
	for i in 200:
		var x := float(i) * 0.137
		if Display.snapf(x + 7.0) != Display.snapf(x) + 7.0:
			worst += 1
	_check(worst == 0, "snapping commutes with whole-pixel offsets")


func _pictures() -> void:
	var counts := {"spikes_up": 34, "spikes_down": 34, "spikes_left": 34, "spikes_right": 34, "token": 32, "flying_token": 72, "slot": 16}
	_check(PixelShapes.SHAPES.size() == counts.size(), "every shape that was a polygon has a picture")
	for name in counts:
		var shape: Dictionary = PixelShapes.SHAPES[name]
		var rows: Array = shape["rows"]
		var on := 0
		var square := true
		for row: String in rows:
			square = square and row.length() == (rows[0] as String).length()
			on += row.count("#")
		var covered := 0.0
		for box in PixelArt.rects(rows, shape["offset"]):
			covered += box.get_area()
		_check(square and on == counts[name] and int(covered) == on, "%s is a %d x %d picture of %d pixels (%d)" % [name, (rows[0] as String).length(), rows.size(), counts[name], on])
	_check(PixelArt.rects(["#.#", "###"]).size() == 3, "a run along a row is one rect")
	_check(PixelArt.rects(["..#"], Vector2i(5, 7))[0] == Rect2(7, 7, 1, 1), "the offset places the first pixel")
	# The diamonds are symmetrical and the spikes mirror each other.
	var token: Array = PixelShapes.SHAPES["token"]["rows"]
	var flipped := token.duplicate()
	flipped.reverse()
	_check(token == flipped, "the token diamond is the same upside down")
	var up: Array = PixelShapes.SHAPES["spikes_up"]["rows"]
	var down: Array = PixelShapes.SHAPES["spikes_down"]["rows"]
	var up_flipped := up.duplicate()
	up_flipped.reverse()
	_check(up_flipped == down, "spikes pointing down are spikes pointing up, upside down")


func _body() -> void:
	var whole := true
	var squashes := [Vector2.ONE, Vector2(0.9, 1.1), Vector2(1.1, 0.9), Vector2(0.95, 1.05)]
	var pixels := InventoryMarks.pixels(3, true, 1)
	for squash: Vector2 in squashes:
		for i in 40:
			var centre := Vector2(100.0 + float(i) * 0.173, 80.0 + float(i) * 0.311)
			var rects: Array[Rect2] = [PlayerBody.box(centre, squash)]
			rects.append_array(PlayerBody.marks(centre, squash, pixels))
			for box in rects:
				whole = whole and box.position == box.position.round() and box.size == box.size.round()
	_check(whole, "the body and every mark are on whole world pixels at any position and squash")
	_check(PlayerBody.box(Vector2(25, 80), Vector2.ONE) == Rect2(20, 75, 10, 10), "an unsquashed body on a whole centre is the 10 x 10 box")
	var mark := PlayerBody.marks(Vector2(25, 80), Vector2.ONE, [Vector2i(1, 6)] as Array[Vector2i])[0]
	_check(mark == Rect2(21, 81, 1, 1), "a mark is its body pixel")
	_check(PlayerBody.box(Vector2(25, 80), Vector2(0.9, 1.1)).size == Vector2(9, 11), "a squashed body is 9 x 11")


func _world() -> void:
	root.get_node("Save").enabled = false
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	_check(world.camera.zoom == Vector2.ONE * float(Display.RENDER_SCALE), "the world camera is zoomed by the render scale")
	_check(root.oversampling_override == float(Display.RENDER_SCALE), "text is drawn at the render scale")
	for layer in ["Toast", "DebugOverlay", "DevPanel", "MapOverlay"]:
		_check(world.get_node(layer).scale == Vector2.ONE * float(Display.RENDER_SCALE), "%s is drawn at the render scale" % layer)
	var room: Room = world.current
	var platform: MovingPlatform = null
	for child in room.get_children():
		if child is MovingPlatform:
			platform = child
	var whole := platform != null
	if platform != null:
		for tick in range(1, 90, 7):
			platform.move_to(tick)
			for i in 11:
				var at := platform.shown_at(float(i) / 10.0)
				whole = whole and at == at.round()
	_check(whole, "a moving platform is drawn on whole world pixels between ticks")
	_check(platform != null and platform.shown_at(1.0) == Display.snap(room.info.platforms[0].rect_at(85).position), "and at the end of a tick it is where its path is")
	var dust := Player.Dust.new()
	dust.position = Vector2(50.4, 60.5)
	world.add_child(dust)
	for i in 6:
		dust._process(1.0 / 90.0)
		_check(dust.position == dust.position.round(), "a dust speck sits on a whole pixel (%s)" % dust.position)
	world.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		print("FAIL ", message)
		_ok = false
