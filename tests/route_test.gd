extends SceneTree

## Walks the real player through rooms A, B, and C, then back again.


func _initialize() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var player: Player = world.get_node("Player")
	player.scripted = true
	var driver := Driver.new()
	driver.player = player
	driver.host = self
	world.add_child(driver)
	world.move_child(driver, 0)


class Driver extends Node:
	var player: Player
	var host: SceneTree
	var frames := 0
	var phase := "a_wall"
	var jumped_at := -1
	var goal := ""
	var seen: Array[String] = []

	func _physics_process(_delta: float) -> void:
		frames += 1
		var room := _room()
		if seen.is_empty() or seen[seen.size() - 1] != room:
			seen.append(room)
			print("enter %s at %s phase %s" % [room, player.position, phase])
		player.scripted_jump_pressed = false
		player.scripted_jump_held = phase.ends_with("hold")
		_drive(room)
		if frames > 2400:
			_finish(false)

	func _drive(room: String) -> void:
		var local := _local(room)
		match phase:
			"a_wall":
				player.scripted_x = -1.0
				if frames > 25 or player.position.x <= 16.0:
					phase = "a_left"
			"a_left":
				player.scripted_x = 1.0
				if _try_jump_world(22.0, 32.0, "a_left"):
					phase = "jump_hold"
			"a_mid":
				player.scripted_x = 1.0
				if _try_jump_world(96.0, 106.0, "a_mid"):
					phase = "jump_hold"
			"a_top":
				player.scripted_x = 1.0
				if _try_jump_world(176.0, 188.0, "a_top"):
					phase = "jump_hold"
			"a_exit":
				player.scripted_x = 1.0
				if room == "b" and player.input_enabled and player.is_on_floor():
					phase = "b_mid"
			"b_mid":
				player.scripted_x = 1.0
				if _try_jump_local(48.0, 66.0, "b_mid"):
					phase = "jump_hold"
			"b_low":
				player.scripted_x = 1.0
				if _try_jump_local(115.0, 136.0, "b_low"):
					phase = "jump_hold"
			"b_floor":
				player.scripted_x = 1.0
				if player.is_on_floor() and local.y > 155.0 and local.x > 230.0:
					phase = "b_exit"
			"b_exit":
				player.scripted_x = 1.0
				if room == "c" and player.input_enabled and player.is_on_floor():
					phase = "c_in"
			"c_in":
				player.scripted_x = 1.0
				if local.x > 150.0 and player.is_on_floor():
					phase = "c_show"
					jumped_at = frames
			"c_show":
				player.scripted_x = 0.0
				if frames > jumped_at + 50:
					phase = "c_back"
			"c_back":
				player.scripted_x = -1.0
				if room == "b" and player.input_enabled and player.is_on_floor() and local.y > 155.0:
					phase = "up_ready"
			"up_ready":
				player.scripted_x = -1.0
				if player.is_on_floor() and local.x < 110.0:
					phase = "up_low"
			"up_low":
				player.scripted_x = 1.0
				if _try_jump_local(100.0, 130.0, "up_low"):
					phase = "jump_hold"
			"up_mid":
				player.scripted_x = -1.0
				if _try_jump_local(160.0, 190.0, "up_mid"):
					phase = "jump_hold"
			"up_entry":
				player.scripted_x = -1.0
				if _try_jump_local(80.0, 110.0, "up_entry"):
					phase = "jump_hold"
			"b_to_a":
				player.scripted_x = -1.0
				if room == "a" and player.input_enabled and player.is_on_floor():
					phase = "a_done"
					jumped_at = frames
			"a_done":
				player.scripted_x = 0.0
				if frames > jumped_at + 70:
					_finish(_seen("a", "b", "c", "b", "a"))
			"jump_hold":
				player.scripted_x = _hold_x()
				if frames > jumped_at + 8 and player.is_on_floor() and player.input_enabled:
					phase = _after_land()

	func _hold_x() -> float:
		if goal == "up_mid" or goal == "up_entry":
			return -1.0
		return 1.0

	func _after_land() -> String:
		var local := _local(_room())
		print("landed %s at %s" % [goal, local])
		if goal == "a_left" and local.y < 140.0 and local.x > 60.0 and local.x < 115.0:
			return "a_mid"
		if goal == "a_mid" and local.y < 100.0 and local.x > 140.0 and local.x < 195.0:
			return "a_top"
		if goal == "a_top" and local.y < 60.0 and local.x > 230.0:
			return "a_exit"
		if goal == "b_mid" and local.y < 100.0 and local.x > 70.0 and local.x < 145.0:
			return "b_low"
		if goal == "b_low" and local.y > 110.0 and local.y < 145.0 and local.x > 150.0 and local.x < 230.0:
			return "b_floor"
		if goal == "up_low" and local.y > 110.0 and local.y < 145.0 and local.x > 150.0 and local.x < 230.0:
			return "up_mid"
		if goal == "up_mid" and local.y < 100.0 and local.x > 70.0 and local.x < 150.0:
			return "up_entry"
		if goal == "up_entry" and local.y < 60.0 and local.x < 80.0:
			return "b_to_a"
		_finish(false)
		return "jump_hold"

	func _try_jump_world(x_min: float, x_max: float, next_goal: String) -> bool:
		if player.velocity.x > 80.0 and player.is_on_floor() and player.position.x >= x_min and player.position.x <= x_max:
			goal = next_goal
			_jump()
			return true
		return false

	func _try_jump_local(x_min: float, x_max: float, next_goal: String) -> bool:
		var local := _local(_room())
		var moving := player.velocity.x > 80.0 if player.scripted_x > 0.0 else player.velocity.x < -80.0
		if moving and player.is_on_floor() and player.input_enabled and local.x >= x_min and local.x <= x_max:
			goal = next_goal
			_jump()
			return true
		return false

	func _jump() -> void:
		player.scripted_jump_pressed = true
		player.scripted_jump_held = true
		jumped_at = frames
		print("jump %s at %s" % [goal, _local(_room())])

	func _room() -> String:
		return String(host.root.get_node("GameState").current_room_id)

	func _local(room: String) -> Vector2:
		var origin := 0.0
		if room == "b":
			origin = 320.0
		elif room == "c":
			origin = 640.0
		return player.position - Vector2(origin, 0.0)

	func _seen(a: String, b: String, c: String, d: String, e: String) -> bool:
		return seen == [a, b, c, d, e]

	func _finish(ok: bool) -> void:
		print("route %s phase=%s pos=%s visits=%s" % ["pass" if ok else "fail", phase, player.position, seen])
		host.quit(0 if ok else 1)
