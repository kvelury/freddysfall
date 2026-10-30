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
	await _fonts()
	_snapping()
	_pictures()
	_body()
	await _poses()
	await _world()
	print("DISPLAY %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


func _settings() -> void:
	var size := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	_check(size == Display.VIEWPORT and Vector2(size) == Grid.SCREEN_SIZE * float(Display.RENDER_SCALE), "the viewport is the screen size times the render scale (%s)" % size)
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "it still stretches as the viewport, by whole numbers, keeping the aspect")
	_check(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0, "and still filters nearest")
	_check(ProjectSettings.get_setting("display/window/size/window_width_override") == Display.VIEWPORT.x * 2, "the default window is twice the viewport")


func _fonts() -> void:
	var regular: FontFile = UiTheme.FONT
	var bold: FontFile = UiTheme.TITLE_FONT
	_check(regular.resource_path.ends_with("PixelOperator8.ttf") and bold.resource_path.ends_with("PixelOperator8-Bold.ttf"), "the body and title fonts are Pixel Operator 8, regular and bold")
	_check(ProjectSettings.get_setting("gui/theme/custom_font") == "res://assets/fonts/PixelOperator8.ttf", "the project's default font is the body font")
	_check(UiTheme.build().default_font == regular, "the UI theme uses the body font")
	for font: FontFile in [regular, bold]:
		_check(font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and font.hinting == TextServer.HINTING_NONE and font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED and not font.multichannel_signed_distance_field, "%s is imported with no smoothing, hinting or subpixel positioning" % font.resource_path.get_file())
	var title := UiTheme.title_label("Freddy's Fall")
	_check(title.text == "FREDDY'S FALL" and title.get_theme_font("font") == bold, "a title is bold and all capitals")
	title.free()
	var card := TitleCard.new()
	root.add_child(card)
	await process_frame
	card.show_title("The Fall", 1.0)
	_check(card.label.text == "THE FALL" and card.label.get_theme_font("font") == bold, "a title card is bold and all capitals")
	card.free()


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
	var counts := {"spikes_up": 34, "spikes_down": 34, "spikes_left": 34, "spikes_right": 34, "token": 32, "flying_token": 72, "slot": 16, "hud_heart": 38, "hud_slot": 25}
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
	for i in 40:
		var centre := Vector2(100.0 + float(i) * 0.173, 80.0 + float(i) * 0.311)
		var corner := PlayerBody.corner(centre)
		whole = whole and corner == corner.round()
	_check(whole, "the body's corner is on a whole world pixel at any position")
	_check(PlayerBody.corner(Vector2(25, 80)) == Vector2(20, 75), "a body on a whole centre has its corner half a box up and left")
	_check(FreddySprites.problems().is_empty(), "Freddy's pictures are all 10 wide, of pixels, inside the box %s" % FreddySprites.problems())
	var complete := true
	var total := 0
	for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
		var table := FreddySprites.animation(pose)
		complete = complete and table != null and not table.frames.is_empty()
		total += table.frames.size() if table != null else 0
	_check(complete and FreddySprites.frames().size() == total, "every pose has an animation with its pictures (%d)" % total)
	_check(FreddySprites.animation(PlayerAnimator.Pose.WALK).frames.size() == FreddySprites.WALK_LEGS.size() and FreddySprites.animation(PlayerAnimator.Pose.STAND).frames.size() == 1, "and the walk is as long as its legs")
	_check(FreddySprites.SIZE == Grid.CELL, "the pictures' box is the player's box")
	var pictures := 0
	var inside := true
	for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
		for index in FreddySprites.animation(pose).frames.size():
			for facing in [1, -1]:
				var drawn := FreddySprites.rects(pose, index, facing, 3, true)
				var boxes: Array[Rect2] = []
				for layer in drawn.layers:
					boxes.append_array(layer.rects)
				for box: Rect2 in boxes:
					var whole_box := box.position == box.position.round() and box.size == box.size.round()
					inside = inside and whole_box and Rect2(0, 0, 10, 10).encloses(box)
				pictures += 1
	_check(inside, "every picture of Freddy, mirrored or marked, is whole pixels inside the 10 x 10 box (%d drawn)" % pictures)
	var right := FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 0, false)
	var left := FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, -1, 0, false)
	var mirrored := right.layers.size() == left.layers.size()
	for i in right.layers.size():
		mirrored = mirrored and right.layers[i].rects.size() == left.layers[i].rects.size()
		for box in right.layers[i].rects:
			mirrored = mirrored and left.layers[i].rects.has(Rect2(10.0 - box.end.x, box.position.y, box.size.x, box.size.y))
	_check(mirrored, "facing left is facing right mirrored")
	var walk_length: int = FreddySprites.animation(PlayerAnimator.Pose.WALK).frames.size()
	_check(FreddySprites.rects(PlayerAnimator.Pose.WALK, 3, 1, 0, false) == FreddySprites.rects(PlayerAnimator.Pose.WALK, 3 + walk_length, 1, 0, false), "a picture is drawn once and the walk wraps")
	_check(FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 3, true) == FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 3, true) and FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 3, true) != FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 2, true), "and a repeat call returns the same picture, a different inventory another")
	var marked := FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 1, false)
	_check(marked.rects_in(Color.BLACK).has(Rect2(1, 6, 2, 1)), "a token is cut black from the picture")
	# Colour option 1 of the user's sheet: lime body and legs, white eyes, black pupils.
	var lime := Color("c6fb65")
	var body := right.rects_in(lime)
	var eyes := right.rects_in(Color.WHITE)
	var pupils := right.rects_in(Color.BLACK)
	_check(FreddySprites.COLOURS["#"] == lime and FreddySprites.COLOURS["="] == lime and FreddySprites.COLOURS["+"] == Color.WHITE and FreddySprites.COLOURS["o"] == Color.BLACK, "Freddy's body and legs are lime #c6fb65, his eyes white, his pupils black")
	var legs: Array[Rect2] = []
	for layer in right.layers:
		if layer.pixel == "=":
			legs = layer.rects
	_check(right.layers.size() == 5 and legs.has(Rect2(0, 9, 3, 1)) and legs.has(Rect2(7, 9, 3, 1)) and legs.all(func(r: Rect2) -> bool: return r.position.y >= 8), "his legs are their own layer, rows 8 and 9, so they can be recoloured alone")
	var two_pupils: Array[Rect2] = [Rect2(2, 1, 1, 1), Rect2(8, 1, 1, 1)]
	_check(eyes.has(Rect2(1, 0, 3, 1)) and eyes.has(Rect2(7, 0, 3, 1)) and pupils == two_pupils, "his eye stalks are white with a black pupil each (%s, %s)" % [eyes, pupils])
	_check(body.has(Rect2(0, 2, 10, 1)) and body.has(Rect2(0, 9, 3, 1)) and body.has(Rect2(7, 9, 3, 1)), "and his head, body and feet are lime")
	var palette_ok := true
	for c in FreddySprites.COLOURS:
		palette_ok = palette_ok and c.length() == 1 and c != FreddySprites.EMPTY
	for c in FreddySprites.BODY_PIXELS + FreddySprites.MARK_PIXEL:
		palette_ok = palette_ok and FreddySprites.COLOURS.has(c)
	_check(palette_ok, "every colour is one character, and the body pixels and the mark pixel have colours")
	# The user's drawing of him standing (a screen capture; its yellow patch was drawn a few pixels off the grid
	# and is snapped to columns 6-9, rows 4-7). The legs, eyes and notch are as they were.
	var drawing: Array[String] = [
		".+++...+++",
		".+o+...+o+",
		"##########",
		"########..",
		"######yyyy",
		"######yyyy",
		"######yyyy",
		"######yyyy",
		".==....==.",
		"===....===",
	]
	_check(Array(FreddySprites.animation(PlayerAnimator.Pose.STAND).frames[0].rows) == drawing, "Freddy standing is the user's drawing, with the yellow patch on his front flank")
	var yellow := Color("f6ec00")
	_check(FreddySprites.COLOURS["y"] == yellow and _cells(right.rects_in(yellow)) == _block(6, 4, 4, 4), "the patch is one yellow block, columns 6 to 9 and rows 4 to 7")
	_check(_cells(left.rects_in(yellow)) == _block(0, 4, 4, 4), "and facing left it is on the left, the front")
	var patched := true
	for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
		for index in FreddySprites.animation(pose).frames.size():
			patched = patched and not FreddySprites.rects(pose, index, 1, 0, false).rects_in(yellow).is_empty()
	_check(patched, "every picture has the patch: standing, each walk picture, the jump and the landing")
	var cut_patch := FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 0, true).rects_in(Color.BLACK)
	_check(cut_patch.has(Rect2(4, 7, 5, 1)) and FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 0, true).rects_in(yellow).has(Rect2(6, 4, 4, 1)), "marks are cut from the patch as they are from the lime body")


## The cells of rects, sorted, for comparing pictures however the rects are cut up.
func _cells(boxes: Array[Rect2]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for box in boxes:
		for y in int(box.size.y):
			for x in int(box.size.x):
				out.append(Vector2i(int(box.position.x) + x, int(box.position.y) + y))
	out.sort()
	return out


## The cells of a block, sorted.
func _block(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for j in h:
		for i in w:
			out.append(Vector2i(x + i, y + j))
	out.sort()
	return out


## Which picture the body is given: standing, the walk pictures in turn, the
## air, and a short landing. `PlayerAnimator` on its own, then once through a
## real player on the engine's ticks.
func _poses() -> void:
	var dt := 1.0 / 60.0
	var walk: FreddySprites.Clip = FreddySprites.animation(PlayerAnimator.Pose.WALK)
	var a := PlayerAnimator.new()
	a.advance(dt, true, 0.0)
	_check(a.pose == PlayerAnimator.Pose.STAND and _index(a) == 0, "standing still stands")
	var steps: Array[int] = []
	for i in 40:
		a.advance(dt, true, 90.0)
		steps.append(_index(a))
	_check(a.pose == PlayerAnimator.Pose.WALK, "running walks")
	var seen := {}
	for step in steps:
		seen[step] = true
	_check(seen.size() == walk.frames.size(), "and goes through all %d pictures (%d seen)" % [walk.frames.size(), seen.size()])
	_check(steps[1] == 0 and steps[5] == 1 and steps[9] == 2, "a picture every 6 px: at 1.5 px a frame, 3 px is the first, 9 px the second and 15 px the third (%s)" % [steps.slice(0, 10)])
	_check(walk.index(0.0, 3.0) == 0 and walk.index(0.0, 9.0) == 1 and walk.index(0.0, 15.0) == 2 and walk.index(99.0, 3.0) == 0, "the walk goes by the distance run, whatever the time: 3 px the first picture, 9 px the second, 15 px the third")
	_check(walk.index(0.0, 6.0 * walk.frames.size() + 3.0) == 0, "and wraps")
	_check(a.time_in_pose > 0.5 and a.distance_in_pose > 20.0, "and time and distance in the pose have been counting (%.2f s, %.1f px)" % [a.time_in_pose, a.distance_in_pose])
	a.advance(dt, true, -90.0)
	_check(a.pose == PlayerAnimator.Pose.WALK, "running left walks too")
	a.advance(dt, true, 0.5)
	_check(a.pose == PlayerAnimator.Pose.STAND and is_equal_approx(a.time_in_pose, dt) and a.distance_in_pose == 0.5 * dt, "under 1 px/s stands, and time and distance start again (%.4f s, %.4f px)" % [a.time_in_pose, a.distance_in_pose])
	a.advance(dt, true, 90.0)
	_check(a.pose == PlayerAnimator.Pose.WALK and is_equal_approx(a.time_in_pose, dt) and is_equal_approx(a.distance_in_pose, 1.5) and _index(a) == 0, "and the walk starts from the first picture again, one frame's run in (%.4f s, %.4f px)" % [a.time_in_pose, a.distance_in_pose])
	a.advance(dt, false, 90.0)
	_check(a.pose == PlayerAnimator.Pose.JUMP and _index(a) == 0 and is_equal_approx(a.time_in_pose, dt) and a.distance_in_pose == 0.0, "in the air is the jump picture, and the ground run does not count in the air")
	a.advance(dt, false, 90.0)
	_check(is_equal_approx(a.time_in_pose, 2.0 * dt) and a.distance_in_pose == 0.0, "and time carries on in the pose")
	a.land()
	var landing := 0
	for i in 20:
		a.advance(dt, true, 90.0)
		if a.pose == PlayerAnimator.Pose.LAND:
			landing += 1
			if landing == 1:
				_check(is_equal_approx(a.time_in_pose, dt) and is_equal_approx(a.distance_in_pose, 1.5), "landing starts the pose's time and distance from 0")
	_check(landing == 8, "landing shows for an eighth of a second, 8 frames at 60 (%d)" % landing)
	_check(a.pose == PlayerAnimator.Pose.WALK and is_equal_approx(a.time_in_pose, 12.0 * dt) and is_equal_approx(a.distance_in_pose, 12.0 * 1.5), "and then walks on, counting from the end of the landing, not from before (%.4f s, %.2f px)" % [a.time_in_pose, a.distance_in_pose])
	# An animation by time loops or holds its last picture.
	var timed := FreddySprites.Clip.new()
	timed.frames = [FreddySprites.Frame.new(0, [], [], []), FreddySprites.Frame.new(0, [], [], []), FreddySprites.Frame.new(0, [], [], [])]
	timed.every = 0.1
	_check(timed.index(0.05, 99.0) == 0 and timed.index(0.15, 0.0) == 1 and timed.index(0.25, 0.0) == 2 and timed.index(0.35, 0.0) == 0, "an animation by time changes picture every `every` seconds and loops")
	timed.loop = false
	_check(timed.index(0.35, 0.0) == 2 and timed.index(9.0, 0.0) == 2, "and one that does not loop holds the last")
	timed.every = 0.0
	_check(timed.index(9.0, 99.0) == 0, "and an `every` of 0 is the first picture only")

	var player: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	player.scripted = true
	var holder := Node2D.new()
	root.add_child(holder)
	holder.add_child(player)
	var floor_rects: Array[Rect2] = [Rect2(0, 100, 400, 20)]
	player.place(Vector2(50, 95), floor_rects)
	player.scripted_x = 1.0
	var walked := false
	for i in 40:
		await physics_frame
		walked = walked or player.animator.pose == PlayerAnimator.Pose.WALK
	_check(walked, "a running player walks")
	player.scripted_x = 0.0
	player.scripted_jump_pressed = true
	player.scripted_jump_held = true
	var jumped := false
	var landed := false
	for i in 120:
		await physics_frame
		await process_frame
		jumped = jumped or player.animator.pose == PlayerAnimator.Pose.JUMP
		landed = landed or (jumped and player.animator.pose == PlayerAnimator.Pose.LAND)
		if i == 10:
			player.scripted_jump_held = false
	_check(jumped and landed, "a jumping player shows the jump, then lands (%s, %s)" % [jumped, landed])
	holder.free()


## The picture index the animator's time and distance give for its pose.
func _index(a: PlayerAnimator) -> int:
	return FreddySprites.animation(a.pose).index(a.time_in_pose, a.distance_in_pose)


func _world() -> void:
	root.get_node("Save").enabled = false
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	_check(world.camera.zoom == Vector2.ONE * float(Display.RENDER_SCALE), "the world camera is zoomed by the render scale")
	_check(root.oversampling_override == float(Display.RENDER_SCALE), "text is drawn at the render scale")
	for layer in ["Toast", "DebugOverlay", "DevPanel", "MapOverlay", "Hud"]:
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
