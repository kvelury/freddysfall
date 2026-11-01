extends SceneTree

## Lashing up: with the jump key held when lash is pressed, the tongue goes
## straight up out of the top of Freddy's head. It stops at a solid above him,
## keeps going when he turns, and shows the looking-up picture with a vertical
## pink line from the notch on top. A press with no key held still lashes the
## way he faces. (Breaking a wall overhead is tested in room 12's play test.)

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var ok := true
	ok = _picture() and ok
	ok = await _play() and ok
	print("LASH UP %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond


func _picture() -> bool:
	var ok := true
	ok = _check(FreddySprites.problems().is_empty(), "every picture is valid, the looking-up one too (%s)" % [FreddySprites.problems()]) and ok
	var clip := FreddySprites.animation(PlayerAnimator.Pose.LASH_UP)
	ok = _check(clip != null and clip.frames.size() == 1 and clip.frames[0].mouth_up == Vector2i(4, 2), "looking up has one picture, with the mouth on top") and ok
	var row: String = clip.frames[0].rows[2]
	ok = _check(row.substr(4, 2) == ".." and row.substr(0, 4) == "####", "the notch is open on top of the body (%s)" % row) and ok
	var a := PlayerAnimator.new()
	a.advance(0.016, true, 0.0, true)
	ok = _check(a.pose == PlayerAnimator.Pose.LASH_UP, "lashing up shows it") and ok
	a.advance(0.016, false, 0.0, true)
	ok = _check(a.pose == PlayerAnimator.Pose.LASH_UP, "in the air too") and ok
	a.advance(0.016, false, 0.0, false)
	ok = _check(a.pose == PlayerAnimator.Pose.JUMP, "and when it is over, the pose follows what the body does") and ok
	return ok


func _play() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	state.reset()
	state.abilities.tongue_unlocked = true
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	player.scripted = true
	tongue.scripted = true
	var room: Room = world.current
	# Two cells under the room's ceiling, on the left. The player is falling, so
	# the lash is made at once and it only has a few ticks to reach the ceiling.
	player.place(room.position + Grid.cell_center(Vector2i(3, 3)), room.world_rects())
	player.facing = 1
	ok = _check(tongue.lash(true) and tongue.up and tongue.active and player.lashing_up, "held up, a press lashes up") and ok
	var tip: Vector2 = tongue.tip()
	ok = _check(is_equal_approx(tip.x, player.global_position.x) and tip.y < player.global_position.y - 4.0, "the tip is above the head, not in front of it") and ok
	var farthest := 0.0
	for i in 40:
		await physics_frame
		farthest = maxf(farthest, tongue.extension)
		if not tongue.active:
			break
	# The ceiling's underside is 20 px above the top of the body.
	ok = _check(farthest > 16.0 and farthest < 27.0, "it stops at the ceiling (%.1f px)" % farthest) and ok
	ok = _check(not tongue.active and not player.lashing_up and tongue.cooldown_left > 0.0, "then it is back in and the picture ends") and ok
	# Turning does not cut an up-lash short.
	for i in 30:
		if tongue.cooldown_left <= 0.0:
			break
		await physics_frame
	player.place(room.position + Grid.cell_center(Vector2i(17, 40)), room.world_rects())
	tongue.lash(true)
	player.facing = -1
	await physics_frame
	ok = _check(tongue.active and tongue.up, "turning round does not pull it in") and ok
	tongue.clear()
	ok = _check(not tongue.up and not player.lashing_up, "clearing it clears the picture too") and ok
	# Without the key it goes the way he faces.
	player.facing = -1
	ok = _check(tongue.lash(false) and not tongue.up and tongue.direction == -1 and tongue.tip().x < player.global_position.x, "with no key held it lashes sideways as before") and ok
	var body := player.get_node("Visual") as PlayerBody
	tongue.clear()
	player.animator.pose = PlayerAnimator.Pose.LASH_UP
	body.show_at(player.global_position, PlayerAnimator.Pose.LASH_UP, 0)
	body.facing = 1
	var rect := body.tongue_rect_up(20.0)
	ok = _check(rect.size == Vector2(1.0, 23.0) and is_equal_approx(rect.position.x, body.position.x + 4.0) and is_equal_approx(rect.position.y, body.position.y - 20.0), "the pink line is one column from the notch to 20 px above the head (%s)" % rect) and ok
	body.facing = -1
	rect = body.tongue_rect_up(20.0)
	ok = _check(is_equal_approx(rect.position.x, body.position.x + 5.0), "mirrored when he faces left (%s)" % rect) and ok
	return ok
