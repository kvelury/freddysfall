extends TestCase

## Looking up and down. The eyes change at once (the pictures), and the view
## shifts a quarter of a screen only after the key has been held 1.15 s, from the
## ground only: on any ground (a moving platform too), never in the air or on a
## Tongue Climb hang. The shift is clamped by the room, ignored by a one-screen
## room, and gone at once when the player is placed again.

const HALF := 45.0


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var ok := true
	ok = _look_ahead() and ok
	ok = _camera() and ok
	ok = _pictures() and ok
	ok = await _play() and ok
	finish("LOOK", ok)


func _look_ahead() -> bool:
	var ok := true
	var look := LookAhead.new()
	for i in 68:
		look.step(1.0 / 60.0, -1)
	ok = check(look.offset() == 0.0, "held for just under 1.15 s, nothing has moved") and ok
	look.step(1.0 / 60.0, -1)
	look.step(1.0 / 60.0, -1)
	ok = check(look.offset() < 0.0 and look.offset() > -LookAhead.OFFSET, "after 1.15 s it starts to glide up (%s)" % look.offset()) and ok
	for i in 20:
		look.step(1.0 / 60.0, -1)
	ok = check(is_equal_approx(look.offset(), -HALF), "and arrives a quarter of a screen up (%s)" % look.offset()) and ok
	for i in 20:
		look.step(1.0 / 60.0, 0)
	ok = check(look.offset() == 0.0, "letting go glides it back") and ok
	for i in 100:
		look.step(1.0 / 60.0, 1)
	ok = check(is_equal_approx(look.offset(), HALF), "down is a quarter of a screen the other way (%s)" % look.offset()) and ok
	look.step(1.0 / 60.0, -1)
	ok = check(look.held_time < 0.1, "changing direction restarts the hold") and ok
	look.reset()
	ok = check(look.offset() == 0.0 and look.progress == 0.0 and look.held_dir == 0, "reset puts it at rest") and ok
	return ok


func _camera() -> bool:
	var ok := true
	var tall := Vector2(320, 720)
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 275), 0.0).y == 275.0, "no look, no shift") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 275), -HALF).y == 230.0, "looking up moves the view up 45") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 275), HALF).y == 320.0, "looking down moves it down 45") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 60), -HALF).y == 90.0, "the view stops at the top of the room") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 700), HALF).y == 630.0, "and at the bottom") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 700), -HALF).y == 585.0, "a player against the bottom still sees above") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, Vector2(320, 180), Vector2(160, 90), -HALF).y == 90.0, "a one-screen-tall room does not scroll") and ok
	ok = check(Grid.camera_focus(Vector2.ZERO, Vector2(640, 180), Vector2(300, 90), HALF).y == 90.0, "nor does a wide one") and ok
	var shifted := Grid.camera_focus(Vector2.ZERO, tall, Vector2(160, 275), -17.3)
	ok = check(shifted == shifted.round(), "the view is on whole pixels") and ok
	return ok


func _pictures() -> bool:
	var ok := true
	ok = check(FreddySprites.problems().is_empty(), "every picture is valid (%s)" % [FreddySprites.problems()]) and ok
	var down := FreddySprites.animation(PlayerAnimator.Pose.LOOK_DOWN)
	var stand := FreddySprites.animation(PlayerAnimator.Pose.STAND)
	ok = check(down != null and down.frames.size() == 1 and down.frames[0].rows != stand.frames[0].rows, "looking down has its own picture") and ok
	var halves := FreddySprites.fine_rects(PlayerAnimator.Pose.LOOK_DOWN, 0, 1)
	ok = check(halves == [Rect2(2, 1.5, 1, 0.5), Rect2(8, 1.5, 1, 0.5)], "its pupils are half a pixel tall on the bottom of the eye row (%s)" % [halves]) and ok
	ok = check(FreddySprites.fine_rects(PlayerAnimator.Pose.LOOK_DOWN, 0, -1) == [Rect2(7, 1.5, 1, 0.5), Rect2(1, 1.5, 1, 0.5)], "and mirror when he faces left") and ok
	ok = check(FreddySprites.fine_rects(PlayerAnimator.Pose.STAND, 0, 1).is_empty() and FreddySprites.fine_rects(PlayerAnimator.Pose.LOOK_UP, 0, 1).is_empty(), "no other picture has any")  and ok
	var a := PlayerAnimator.new()
	a.advance(0.016, true, 0.0, false, false, PlayerAnimator.Hang.NONE, true)
	ok = check(a.pose == PlayerAnimator.Pose.LOOK_DOWN, "standing still with the look-down key held looks down") and ok
	a.advance(0.016, true, 60.0, false, false, PlayerAnimator.Hang.NONE, true)
	ok = check(a.pose == PlayerAnimator.Pose.WALK, "walking keeps the walk picture") and ok
	a.advance(0.016, false, 0.0, false, false, PlayerAnimator.Hang.NONE, true)
	ok = check(a.pose == PlayerAnimator.Pose.JUMP, "so does the air") and ok
	a.advance(0.016, true, 0.0, true, false, PlayerAnimator.Hang.NONE, true)
	ok = check(a.pose == PlayerAnimator.Pose.LASH_UP, "and the tongue going up") and ok
	return ok


func _play() -> bool:
	var ok := true
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var camera: Camera2D = world.get_node("Camera2D")
	player.scripted = true
	var room: Room = world.current
	var ledge := room.position + Grid.cell_center(Vector2i(17, 27))
	player.place(ledge, room.world_rects())
	await ticks(30)
	await process_frame
	var base := camera.position.y

	# Up: nothing for 1.15 s, then a quarter of a screen.
	player.scripted_look_up = true
	await ticks(60)
	await process_frame
	ok = check(camera.position.y == base, "holding up for under 1.15 s leaves the view alone (%s)" % camera.position.y) and ok
	await ticks(30)
	await process_frame
	ok = check(is_equal_approx(camera.position.y, base - HALF), "after 1.15 s the view is 45 px up (%s from %s)" % [camera.position.y, base]) and ok
	# Walking along the ground does not cancel it.
	player.scripted_x = 1.0
	await ticks(5)
	player.scripted_x = 0.0
	ok = check(player.look.progress == -1.0, "walking on the ground keeps it") and ok
	player.scripted_look_up = false
	await ticks(20)
	await process_frame
	ok = check(is_equal_approx(camera.position.y, base) or absf(camera.position.y - base) < 10.0, "letting go brings it back (%s)" % camera.position.y) and ok

	# Down.
	player.place(ledge, room.world_rects())
	await ticks(30)
	await process_frame
	base = camera.position.y
	player.scripted_look_down = true
	await ticks(105)
	await process_frame
	ok = check(is_equal_approx(camera.position.y, base + HALF), "down moves the view 45 px down (%s from %s)" % [camera.position.y, base]) and ok
	player.scripted_look_up = true
	await ticks(3)
	ok = check(not player.looking_up and not player.looking_down and player.look.held_dir == 0, "both keys together cancel each other") and ok
	player.scripted_look_up = false

	# The air and a hang give no shift, and a jump cancels what was there.
	player.scripted_jump_pressed = true
	player.scripted_jump_held = true
	await ticks(3)
	ok = check(not player.is_on_floor() and player.look.held_dir == 0 and player.look.held_time == 0.0, "in the air the hold starts over") and ok
	player.scripted_jump_held = false
	await ticks(90)
	player.scripted_look_down = false

	# Hanging on a wall by the tongue is no time to move the view either.
	var beside_wall := room.position + Grid.cell_center(Vector2i(1, 27))
	player.place(beside_wall, room.world_rects())
	await ticks(30)
	var stuck := player.begin_climb(Vector2(room.position.x + 10.0, beside_wall.y), Vector2.LEFT, 10.0, 1.0, 400.0, false)
	ok = check(stuck and player.climbing(), "a climb to the left wall begins") and ok
	player.scripted_look_up = true
	await ticks(100)
	ok = check(player.climbing() and player.look.progress == 0.0, "no shift in 3 s of looking up from a hang (%s)" % player.look.progress) and ok
	player.scripted_look_up = false
	player.end_climb()
	await ticks(60)

	# Placing him again puts the view back at once.
	player.scripted_look_up = true
	player.place(ledge, room.world_rects())
	await ticks(105)
	ok = check(player.look.progress == -1.0, "raised again") and ok
	player.place(ledge, room.world_rects())
	ok = check(player.look.progress == 0.0 and player.look_offset(1.0) == 0.0, "placing the player resets the look") and ok
	player.scripted_look_up = false

	# A moving platform is ground like any other.
	var lift_rect: Rect2 = room.movers.rects(room.tick)[0]
	var lift := lift_rect.position + Vector2(lift_rect.size.x * 0.5, -5.0)
	player.place(lift, room.world_rects())
	await ticks(20)
	ok = check(player.riding() >= 0, "standing on the lift in room 7 (riding %s)" % player.riding()) and ok
	player.scripted_look_up = true
	await ticks(100)
	ok = check(player.look.progress == -1.0, "looking up works while riding a moving platform") and ok
	player.scripted_look_up = false
	world.queue_free()
	return ok
