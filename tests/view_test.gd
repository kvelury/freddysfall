extends TestCase

## A room's camera view: how many screens it shows. Pure geometry (RoomView),
## the world.json setting and its checks, the dev override, and the world's
## camera: zoom 2 in a one-screen view and 1 in a two-screen one, a glide with
## the door slide, a cut for every placement.

const ONE := Vector2(320, 180)
const TWO := Vector2(640, 360)


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var ok := true
	ok = _geometry() and ok
	ok = _data() and ok
	ok = await _world() and ok
	finish("VIEW", ok)


func _geometry() -> bool:
	var ok := true
	ok = check(RoomView.allowed() == [1, 2] and Display.RENDER_SCALE == 2, "at render scale 2 the allowed views are 1 and 2 (%s)" % [RoomView.allowed()]) and ok
	ok = check(RoomView.zoom_for(ONE) == Vector2(2, 2) and RoomView.zoom_for(TWO) == Vector2.ONE, "one screen zooms by 2, two by 1") and ok
	ok = check(RoomView.size(2) == TWO and RoomView.size(1) == Grid.SCREEN_SIZE, "a view's size is that many screens") and ok
	ok = check(RoomView.look_scale(ONE) == 1.0 and RoomView.look_scale(TWO) == 2.0, "looking shifts a quarter of the view") and ok
	# With one screen it is Grid.camera_focus exactly.
	var same := true
	for room_size in [Vector2(320, 180), Vector2(640, 180), Vector2(320, 720), Vector2(1280, 360)]:
		for focus in [Vector2(10, 10), Vector2(160, 275), Vector2(700, 90), Vector2(1200, 700)]:
			for look in [0.0, -45.0, 45.0, 17.3]:
				var origin := Vector2(320, 180)
				same = same and RoomView.camera_focus(origin, room_size, ONE, focus + origin, look) == Grid.camera_focus(origin, room_size, focus + origin, look)
	ok = check(same, "a one-screen view follows exactly as Grid.camera_focus does") and ok
	# Room 18 is 4 x 2 screens, room 19 is 2 x 4.
	var wide := Vector2(1280, 360)
	var tall := Vector2(640, 720)
	var at := RoomView.camera_focus(Vector2.ZERO, wide, TWO, Vector2(100, 50))
	ok = check(at == Vector2(320, 180), "a 4 x 2 room in a two-screen view stops at its left edge and centres vertically (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, wide, TWO, Vector2(1200, 300))
	ok = check(at == Vector2(960, 180), "and at its right edge (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, tall, TWO, Vector2(100, 50))
	ok = check(at == Vector2(320, 180), "a 2 x 4 room centres across and stops at its top (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, tall, TWO, Vector2(500, 700))
	ok = check(at == Vector2(320, 540), "and at its bottom (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, tall, TWO, Vector2(320, 700), 90.0)
	ok = check(at == Vector2(320, 540), "looking down there still stops at the room's edge (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, tall, TWO, Vector2(320, 400), 90.0)
	ok = check(at == Vector2(320, 490), "looking down in the middle shifts a quarter of the view (%s)" % at) and ok
	at = RoomView.camera_focus(Vector2.ZERO, TWO, TWO, Vector2(100, 100), -90.0)
	ok = check(at == Vector2(320, 180), "a room exactly as big as the view never scrolls") and ok
	at = RoomView.camera_focus(Vector2(640, 0), ONE, TWO, Vector2(700, 20))
	ok = check(at == Vector2(800, 90), "a room smaller than the view is centred (the dev override)") and ok
	ok = check(RoomView.fits(2, Vector2i(4, 2)) and RoomView.fits(2, Vector2i(2, 4)) and not RoomView.fits(2, Vector2i(2, 1)) and not RoomView.fits(2, Vector2i(1, 2)), "a view needs the room to be that many screens both ways") and ok
	return ok


func _data() -> bool:
	var ok := true
	var data: Node = root.get_node("WorldData")
	data.ensure_loaded()
	ok = check(data.errors.is_empty(), "the world loads clean (%s)" % [data.errors]) and ok
	ok = check(data.view_of("16") == 2 and data.view_of("18") == 2 and data.view_of("19") == 2, "rooms 16, 18 and 19 show two screens") and ok
	ok = check(data.view_of("2") == 1 and data.view_of("nothing") == 1, "every other room shows one") and ok
	var small = preload("res://src/autoload/world_data.gd").new()
	var problems: Array[String] = []
	ok = check(small.read_view(2, "x", problems) == 2 and small.read_view(2.0, "x", problems) == 2 and small.read_view(1, "x", problems) == 1 and problems.is_empty(), "1 and 2 are views") and ok
	for bad in [3, 0, -1, 1.5, "2", null, true]:
		problems.clear()
		ok = check(small.read_view(bad, "x", problems) == 1 and problems.size() == 1, "%s is not a view" % [bad]) and ok
	# A view bigger than the room is an error and is dropped.
	small.load_from("res://tests/fixtures/worlds/view/world.json", "res://tests/fixtures/worlds/view/rooms/")
	ok = check(small.errors.size() == 1 and String(small.errors[0]).contains("view of 2 screens") and small.view_of("1") == 1 and small.view_of("2") == 2, "a two-screen view on a one-screen room is refused, on a 2 x 2 room it is kept (%s)" % [small.errors]) and ok
	small.errors.clear()
	small.free()
	return ok


func _world() -> bool:
	var ok := true
	root.get_node("Save").enabled = false
	var session: Node = root.get_node("DevSession")
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "18"
	root.add_child(world)
	await process_frame
	var player: Player = world.player
	player.scripted = true
	var camera: Camera2D = world.camera
	ok = check(camera.zoom == Vector2.ONE, "room 18 is drawn two screens") and ok
	var door: Door = null
	for candidate in world.current.info.exits:
		if candidate.dest_id == "s4":
			door = candidate
	ok = check(door != null, "room 18 has a door into s4, a one-screen room") and ok
	if door == null:
		world.queue_free()
		return false
	world._on_exit(door)
	await ticks(4)
	ok = check(camera.zoom.x > 1.0 and camera.zoom.x < 2.0, "crossing into s4 glides the zoom in (%s)" % camera.zoom) and ok
	var early := camera.zoom.x
	await ticks(8)
	ok = check(camera.zoom.x > early, "and keeps going (%s -> %s)" % [early, camera.zoom.x]) and ok
	await until(func() -> bool: return not world.is_busy(), 120)
	ok = check(world.current.info.id == "s4" and camera.zoom == Vector2(2, 2), "it ends at zoom 2 in room s4 (%s)" % camera.zoom) and ok
	var want := RoomView.camera_focus(world.current.position, world.current.info.pixel_size, ONE, player.global_position)
	ok = check(camera.position == want, "with the camera where a one-screen view puts it (%s, wanted %s)" % [camera.position, want]) and ok
	world.warp_to("18")
	var shown := get_root_view_rect(camera)
	ok = check(shown.size == TWO and shown.position.y == world.current.position.y, "18 shows two screens, top to bottom (%s)" % shown) and ok
	# A placement is a cut.
	world.warp_to("2")
	ok = check(camera.zoom == Vector2(2, 2), "warping to a one-screen room cuts back to zoom 2") and ok
	world.warp_to("19")
	ok = check(camera.zoom == Vector2.ONE, "and into 19 cuts to zoom 1") and ok
	# Dying and coming back keeps the room's view.
	world._respawn(false)
	await ticks(2)
	ok = check(camera.zoom == Vector2.ONE or world.current.info.id != "19", "a respawn does not leave a stale zoom") and ok

	# The dev override.
	world.warp_to("2")
	ok = check(session.view_for("2") == 1 and session.set_view_override(world, 2) != "", "an override is refused outside a dev test") and ok
	ok = check(session.enter(world).is_empty(), "enter a dev test") and ok
	ok = check(session.set_view_override(world, 3) != "" and session.view_override == 0, "a view the render scale cannot draw is refused") and ok
	ok = check(session.set_view_override(world, 2).is_empty() and camera.zoom == Vector2.ONE and session.view_for("2") == 2, "forcing two screens zooms room 2 out at once") and ok
	ok = check(camera.position == Vector2(world.current.position + Vector2(160, 90)).round(), "and centres the small room (%s)" % camera.position) and ok
	ok = check(session.status_line().contains("view 2 screens"), "the pause menu says so (%s)" % session.status_line()) and ok
	ok = check(session.next_view() == 0, "F8 goes on to the room's own view") and ok
	ok = check(session.set_view_override(world, 0).is_empty() and camera.zoom == Vector2(2, 2), "back to the room's own view") and ok
	ok = check(session.next_view() == 1, "and then to one screen") and ok
	session.set_view_override(world, 1)
	world.warp_to("18")
	ok = check(camera.zoom == Vector2(2, 2) and session.view_for("18") == 1, "an override of one screen zooms room 18 in") and ok
	ok = check(not session.loadout.has("view_override") and not root.get_node("GameState").to_dict().has("view_override"), "the override is in no loadout or save") and ok
	session.reset_to_normal()
	ok = check(session.view_override == 0 and session.view_for("18") == 2, "returning to a normal game clears it") and ok
	world.queue_free()
	return ok


## The world rect the camera shows.
func get_root_view_rect(camera: Camera2D) -> Rect2:
	var size := Vector2(Display.VIEWPORT) / camera.zoom
	return Rect2(camera.position - size * 0.5, size)
