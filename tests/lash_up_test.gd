extends SceneTree

## Lashing up: with the look-up key (Up or W) held when lash (B) is pressed, the tongue goes
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
	ok = _keys() and ok
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
	# Looking up: standing still only, the same with or without Tongue Lash.
	var look := PlayerAnimator.new()
	look.advance(0.016, true, 0.0, false, true)
	ok = _check(look.pose == PlayerAnimator.Pose.LOOK_UP, "standing still with the look-up key held looks up") and ok
	look.advance(0.016, true, 60.0, false, true)
	ok = _check(look.pose == PlayerAnimator.Pose.WALK, "walking keeps the walk picture") and ok
	look.advance(0.016, false, 0.0, false, true)
	ok = _check(look.pose == PlayerAnimator.Pose.JUMP, "so does the air") and ok
	look.land()
	look.advance(0.016, true, 0.0, false, true)
	ok = _check(look.pose == PlayerAnimator.Pose.LAND, "and landing") and ok
	look.advance(0.5, true, 0.0, false, true)
	look.advance(0.016, true, 0.0, false, true)
	ok = _check(look.pose == PlayerAnimator.Pose.LOOK_UP, "once landed, it looks up again") and ok
	look.advance(0.016, true, 0.0, false, false)
	ok = _check(look.pose == PlayerAnimator.Pose.STAND, "and stands when the key is let go") and ok
	var looking := FreddySprites.animation(PlayerAnimator.Pose.LOOK_UP).frames[0]
	ok = _check(looking.rows[0] == ".+o+...+o+" and looking.mouth == 3 and looking.mouth_up == Vector2i(-1, -1), "the look-up picture has its pupils in the top row and a closed mouth") and ok
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
	ok = _check(not player.looking_up, "not looking up before the key is held") and ok
	player.scripted_look_up = true
	await physics_frame
	await physics_frame
	ok = _check(player.looking_up, "the look-up key held is looking up") and ok
	ok = _check(tongue.lash(true) and tongue.up and tongue.active and player.lashing_up, "held up, a press lashes up") and ok
	var tip: Vector2 = tongue.tip()
	ok = _check(is_equal_approx(tip.x, player.global_position.x) and tip.y < player.global_position.y - 4.0, "the tip is above the head, not in front of it") and ok
	var farthest := 0.0
	var stuck_ys: Array[float] = []
	for i in 40:
		await physics_frame
		if tongue.phase == tongue.Phase.OUT:
			farthest = maxf(farthest, tongue.extension)
		elif tongue.phase == tongue.Phase.STICK:
			stuck_ys.append(tongue.tip().y)
		if not tongue.active:
			break
	# It sticks to the ceiling: the tip stays put while the player falls away.
	ok = _check(stuck_ys.size() >= 2 and absf(stuck_ys[0] - stuck_ys[-1]) < 0.01, "an up-lash sticks to the ceiling, tip fixed (%d ticks)" % stuck_ys.size()) and ok
	# The ceiling's underside is 20 px above the top of the body.
	ok = _check(farthest > 15.0 and farthest < 27.0, "it stops at the ceiling (%.1f px)" % farthest) and ok
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
	# The real keys, not the scripted stand-ins: look up then lash goes up, and lash
	# alone, or jump and lash, goes the way he faces.
	tongue.clear()
	tongue.cooldown_left = 0.0
	tongue.scripted = false
	player.facing = 1
	Input.action_press("jump")
	Input.action_press("lash")
	for i in 3:
		await physics_frame
	var sideways: bool = tongue.active and not tongue.up
	Input.action_release("jump")
	Input.action_release("lash")
	ok = _check(sideways, "with the real keys, jump (Space) and lash (B) lash sideways") and ok
	tongue.clear()
	for i in 3:
		await physics_frame
	Input.action_press("look_up")
	Input.action_press("lash")
	for i in 3:
		await physics_frame
	var upward: bool = tongue.active and tongue.up
	Input.action_release("look_up")
	Input.action_release("lash")
	ok = _check(upward, "with the real keys, look up (W or Up) and lash (B) lash up") and ok
	tongue.clear()
	tongue.scripted = true
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


## The real input path, with no scripting: X alone lashes sideways, Up with X
## lashes up, and Space and Up no longer do each other's job.
func _keys() -> bool:
	var ok := true
	var jump := _codes("jump")
	var look := _codes("look_up")
	var lash := _codes("lash")
	ok = _check(jump == [KEY_SPACE] and lash == [KEY_X] and look.has(KEY_W) and look.has(KEY_UP), "Space jumps, X lashes, W and Up look up") and ok
	ok = _check(not InputMap.action_has_event("look_up", _key(KEY_SPACE)) and not InputMap.action_has_event("jump", _key(KEY_UP)), "Space does not look up and Up does not jump") and ok
	return ok


func _codes(action: String) -> Array:
	var out := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append((event as InputEventKey).physical_keycode)
	return out


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
