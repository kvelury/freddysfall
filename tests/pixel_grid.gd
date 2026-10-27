extends SceneTree

## The pixel check. Needs a renderer, so it is not part of tools/check.sh: run
## it with tools/pixel_check.sh. Modes (after `--`):
##   baseline  capture the world scenarios into build/pixel-baseline/
##   compare   capture them again and check them against the baseline (default)
##   shapes    print the one-bit pictures of the shapes drawn as polygons
## The game's frames are taken with the UI hidden. With --fixed-fps 90 each
## frame is a fixed 1/90 s, so a scenario repeats exactly and the player is
## drawn between physics ticks. Nothing here reads or writes the real save.

const BASELINE := "res://build/pixel-baseline"
const CHECK := "res://build/pixel-check"
const FINE_GROUP := "fine_pixels"
const BASE := Vector2i(320, 180)

var mode := "compare"
var world: Node
var player: Player
var failures: Array[String] = []
var captured := 0
var compared := 0


func _initialize() -> void:
	# A script error inside a coroutine leaves the check waiting forever.
	create_timer(900.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	for arg in OS.get_cmdline_user_args():
		mode = arg
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHECK))
	if mode == "shapes":
		await _shapes()
		quit(0)
		return
	root.get_node("Save").enabled = false
	await _rooms()
	await _idle()
	await _jump()
	await _run_and_land()
	await _death()
	await _lift()
	await _door_slide()
	await _imprint()
	await _shot()
	await _save_hop()
	await _feed()
	if mode == "compare":
		await _text()
		await _mouse()
	if failures.is_empty():
		print("PIXEL pass (%d frames %s)" % [captured, "captured" if mode == "baseline" else "compared"])
		quit(0)
	else:
		for line in failures:
			print("FAIL ", line)
		print("PIXEL fail (%d problems)" % failures.size())
		quit(1)


# --- scenario plumbing --------------------------------------------------


## A fresh world in `room` with the player driven by the script.
func _start(room: String, setup := Callable()) -> void:
	if world != null:
		world.free()
		world = null
	root.get_node("GameState").reset()
	seed(1)
	if setup.is_valid():
		setup.call()
	world = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = room
	root.add_child(world)
	await process_frame
	player = world.get_node("Player")
	player.scripted = true
	world.get_node("Imprint").scripted = true
	world.get_node("Gun").scripted = true
	for layer in ["Toast", "DebugOverlay", "DevPanel", "MapOverlay"]:
		world.get_node(layer).visible = false


func _stand(cell: Vector2i, facing := 1) -> void:
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(cell), room.world_rects())
	player.facing = facing


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


## Takes the frame as the screen shows it. The halos are on the wall clock and
## the fine group is meant to be finer, so both are hidden.
func _grab(name: String) -> void:
	_hide_unchecked(root)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	captured += 1
	if mode == "baseline":
		if image.get_size() != BASE:
			failures.append("%s: baseline is %s, not %s (take it before the change)" % [name, image.get_size(), BASE])
		image.save_png("%s/%s.png" % [BASELINE, name])
		return
	var scale := image.get_width() / BASE.x
	if image.get_size() != BASE * scale:
		failures.append("%s: frame is %s" % [name, image.get_size()])
		return
	image.save_png("%s/%s.png" % [CHECK, name])
	var bad := _on_grid(image, scale)
	if not bad.is_empty():
		failures.append("%s: %s" % [name, bad])
	var want := Image.load_from_file(ProjectSettings.globalize_path("%s/%s.png" % [BASELINE, name]))
	if want == null:
		failures.append("%s: no baseline (run tools/pixel_check.sh --baseline first)" % name)
		return
	compared += 1
	var diff := _differs(image, want, scale)
	if not diff.is_empty():
		failures.append("%s: %s" % [name, diff])


func _hide_unchecked(node: Node) -> void:
	if node is ExitHalo or node.is_in_group(FINE_GROUP):
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_unchecked(child)


## Every `scale` x `scale` block of the frame is one colour.
func _on_grid(image: Image, scale: int) -> String:
	if scale == 1:
		return ""
	var count := 0
	var first := ""
	for y in range(0, image.get_height(), scale):
		for x in range(0, image.get_width(), scale):
			var colour := image.get_pixel(x, y)
			for dy in scale:
				for dx in scale:
					if image.get_pixel(x + dx, y + dy) != colour:
						count += 1
						if first.is_empty():
							first = "world pixel (%d, %d)" % [x / scale, y / scale]
	return "" if count == 0 else "%d screen pixels are off the world-pixel grid, first at %s" % [count, first]


## The frame, taken at its top-left pixel of each block, equals the baseline.
func _differs(image: Image, want: Image, scale: int) -> String:
	var count := 0
	var first := ""
	for y in BASE.y:
		for x in BASE.x:
			if image.get_pixel(x * scale, y * scale) != want.get_pixel(x, y):
				count += 1
				if first.is_empty():
					first = "(%d, %d)" % [x, y]
	return "" if count == 0 else "%d world pixels differ from the baseline, first at %s" % [count, first]


# --- the scenarios ------------------------------------------------------


func _rooms() -> void:
	await _start("s1")
	for id in root.get_node("WorldData").rooms.keys():
		world.warp_to(id)
		await _frames(2)
		await _grab("room_%s" % id)


func _idle() -> void:
	await _start("s1", func() -> void:
		var state: Node = root.get_node("GameState")
		state.tokens = 2
		state.abilities.imprint_unlocked = true)
	await _frames(3)
	await _grab("idle_right")
	player.facing = -1
	await _frames(2)
	await _grab("idle_left")


func _jump() -> void:
	await _start("s1")
	await _frames(3)
	for frame in 70:
		player.scripted_jump_pressed = frame == 0
		player.scripted_jump_held = frame < 25
		player.scripted_x = 1.0 if frame > 10 else 0.0
		await process_frame
		await _grab("jump_%02d" % frame)


func _run_and_land() -> void:
	await _start("s1")
	await _frames(3)
	for frame in 110:
		player.scripted_x = 1.0 if frame < 60 else 0.0
		player.scripted_jump_pressed = frame == 30
		player.scripted_jump_held = frame >= 30 and frame < 40
		await process_frame
		await _grab("run_%03d" % frame)


func _death() -> void:
	await _start("11")
	await _frames(3)
	var room: Room = world.current
	var spike: Vector2i = room.info.hazards[0]
	player.place(room.position + Grid.cell_center(spike), room.world_rects())
	for frame in 50:
		await process_frame
		await _grab("death_%02d" % frame)


func _lift() -> void:
	await _start("7")
	await _frames(2)
	var room: Room = world.current
	var path: PlatformPath = room.info.platforms[0]
	var start := room.position + path.rect_at(0).position
	player.place(start + Vector2(path.rect_at(0).size.x * 0.5, -5.0), room.world_rects())
	for frame in 300:
		await process_frame
		if frame % 6 == 0:
			await _grab("lift_%03d" % frame)


func _door_slide() -> void:
	await _start("4")
	await _frames(3)
	_stand(Vector2i(3, 15))
	player.scripted_x = -1.0
	for frame in 120:
		await process_frame
		if frame % 2 == 0:
			await _grab("slide_%03d" % frame)


func _imprint() -> void:
	await _start("5", func() -> void:
		root.get_node("GameState").abilities.imprint_unlocked = true)
	var tool: Node = world.get_node("Imprint")
	await _frames(3)
	_stand(Vector2i(2, 16))
	await _frames(2)
	tool.scripted_cell = Vector2i(6, 13)
	tool.refresh_preview()
	await _frames(2)
	await _grab("imprint_preview")
	tool.scripted_cell = Vector2i(10, 16)
	tool.refresh_preview()
	await _frames(2)
	await _grab("imprint_blocked")
	tool.scripted_cell = Vector2i(6, 13)
	tool.refresh_preview()
	tool.place()
	for frame in 150:
		await process_frame
		if frame % 4 == 0:
			await _grab("imprint_shrink_%03d" % frame)
	await _frames(40)
	var room: Room = world.current
	var rect := Grid.cell_rect(Rect2i(Vector2i(14, 13), Vector2i(3, 1)))
	rect.position += room.position
	tool.platforms.append(ImprintPlatform.new(rect, 1.5, false, player.global_position.x, player.facing))
	for frame in 150:
		await process_frame
		if frame % 4 == 0:
			await _grab("imprint_classic_%03d" % frame)


func _shot() -> void:
	await _start("7", func() -> void:
		root.get_node("GameState").abilities.gun_unlocked = true)
	var gun: Node = world.get_node("Gun")
	await _frames(3)
	_stand(Vector2i(24, 34), -1)
	await _frames(3)
	gun.fire()
	for frame in 24:
		await process_frame
		await _grab("shot_%02d" % frame)


func _save_hop() -> void:
	await _start("s1")
	await _frames(3)
	_stand(Vector2i(14, 8))
	for frame in 170:
		await process_frame
		if frame % 2 == 0:
			await _grab("save_%03d" % frame)


func _feed() -> void:
	await _start("4", func() -> void:
		root.get_node("GameState").tokens = 2)
	await _frames(3)
	_stand(Vector2i(6, 16))
	player.scripted_x = 1.0
	for frame in 260:
		await process_frame
		if frame % 3 == 0:
			await _grab("feed_%03d" % frame)
		if world.is_busy():
			player.scripted_x = 0.0


# --- the parts that need the UI (compare only) --------------------------


func _text() -> void:
	pass


func _mouse() -> void:
	pass


## Draws each polygon shape with the code as it is, one per known spot on a
## black stage, and prints it as rows of # (on) and . (off), with the offset of
## the top-left pixel from the spot. These become src/core/pixel_shapes.gd.
func _shapes() -> void:
	await _start("s1")
	world.get_node("Rooms").visible = false
	player.visible = false
	var stage := Node2D.new()
	world.add_child(stage)
	var shapes := {}
	var at := Vector2(30, 30)
	for facing in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var chunk := Room.RoomChunk.new()
		chunk.hazards = [Vector2i.ZERO] as Array[Vector2i]
		chunk.facings = [facing] as Array[Vector2i]
		chunk.position = at
		stage.add_child(chunk)
		shapes["spikes_%s" % {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}[facing]] = [at, Rect2i(0, 0, 10, 10)]
		at.x += 30
	var token := Token.new()
	token.position = Vector2(30, 90)
	stage.add_child(token)
	shapes["token"] = [token.position, Rect2i(-6, -6, 12, 12)]
	var pickup := Pickup.new()
	pickup.position = Vector2(60, 90)
	stage.add_child(pickup)
	shapes["pickup"] = [pickup.position, Rect2i(-6, -6, 12, 12)]
	var flier := FlyingToken.new()
	flier.position = Vector2(90, 90)
	stage.add_child(flier)
	flier.process_mode = Node.PROCESS_MODE_DISABLED
	shapes["flying_token"] = [flier.position, Rect2i(-8, -8, 16, 16)]
	var slot := Outline.new()
	slot.position = Vector2(200, 90)
	stage.add_child(slot)
	shapes["slot"] = [slot.position, Rect2i(-6, -6, 12, 12)]
	for node in stage.get_children():
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var out := ""
	for name in shapes:
		var spot: Vector2 = shapes[name][0]
		var box: Rect2i = shapes[name][1]
		var rows: Array[String] = []
		var x0 := 1000
		var x1 := -1
		var y0 := 1000
		var y1 := -1
		for y in box.size.y:
			for x in box.size.x:
				if image.get_pixel(int(spot.x) + box.position.x + x, int(spot.y) + box.position.y + y).r > 0.5:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		out += "%s offset (%d, %d)\n" % [name, box.position.x + x0, box.position.y + y0]
		for y in range(y0, y1 + 1):
			var row := ""
			for x in range(x0, x1 + 1):
				row += "#" if image.get_pixel(int(spot.x) + box.position.x + x, int(spot.y) + box.position.y + y).r > 0.5 else "."
			out += row + "\n"
	print(out)
	var file := FileAccess.open(ProjectSettings.globalize_path("res://build/pixel-shapes.txt"), FileAccess.WRITE)
	file.store_string(out)
	image.save_png(ProjectSettings.globalize_path("res://build/pixel-shapes.png"))


## The empty slot of a 3TM, drawn the way TokenMachine._draw draws it.
class Outline extends Node2D:
	func _draw() -> void:
		var at := Vector2.ZERO
		draw_polyline(PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0), at + Vector2(0, 4), at + Vector2(-4, 0), at + Vector2(0, -4)]), Color.WHITE, 1.0)
