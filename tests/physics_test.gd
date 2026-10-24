extends SceneTree

## Drives the real player through room s1, to confirm the player's own movement
## can make the running jumps the solver says the room asks for. It lands on
## the middle platform, where the save machine takes the player in and pops them
## out on the far side (the right, for a jump from the left). The doors stay shut
## until it has been used, so reaching room 2 also shows that it saves. Popped
## out at the platform's right end with no speed, the test runs back to the left
## end for the run-up the last jump needs.

func _initialize() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var player: Player = world.get_node("Player")
	player.scripted = true
	var driver := Driver.new()
	driver.player = player
	driver.camera = world.get_node("Camera2D")
	driver.host = self
	world.add_child(driver)
	world.move_child(driver, 0)


class Driver extends Node:
	var player: Player
	var camera: Camera2D
	var host: SceneTree
	var frames := 0
	var phase := "to_wall"
	var jumped_at := -1
	var goal := "left"

	func _physics_process(_delta: float) -> void:
		frames += 1
		player.scripted_jump_pressed = false
		player.scripted_jump_held = phase.begins_with("hold")
		player.scripted_x = -1.0 if phase == "to_wall" or phase == "run_back" else 1.0
		if phase == "to_wall":
			if frames > 25 or player.position.x <= 16.0:
				phase = "seek_left"
		elif phase == "seek_left":
			if _try_jump(22.0, 32.0):
				goal = "left"
				phase = "hold"
		elif phase == "hold":
			if frames > jumped_at + 8 and player.is_on_floor():
				phase = _next_seek()
		elif phase == "seek_mid":
			if _try_jump(96.0, 106.0):
				goal = "mid"
				phase = "hold"
		elif phase == "run_back":
			if player.position.x <= 146.0:
				phase = "seek_top"
		elif phase == "seek_top":
			if _try_jump(176.0, 188.0):
				goal = "top"
				phase = "hold"
		elif phase == "exit":
			player.scripted_x = 1.0
			player.scripted_jump_held = false
			var room_id := String(host.root.get_node("GameState").current_room_id)
			if room_id == "2" and camera.position.x >= 470.0 and player.input_enabled:
				_finish(player.position.x > 320.0)
		if frames > 700:
			_finish(false)

	func _try_jump(x_min: float, x_max: float) -> bool:
		if player.velocity.x > 80.0 and player.is_on_floor() and player.position.x >= x_min and player.position.x <= x_max:
			player.scripted_jump_pressed = true
			player.scripted_jump_held = true
			jumped_at = frames
			print("jump for %s at %s" % [goal, player.position])
			return true
		return false

	func _next_seek() -> String:
		var pos := player.position
		print("landed %s at %s" % [goal, pos])
		if goal == "left" and pos.y < 140.0 and pos.x > 60.0 and pos.x < 115.0:
			return "seek_mid"
		if goal == "mid" and pos.y < 100.0 and pos.x > 140.0 and pos.x < 195.0:
			return "run_back"
		if goal == "top" and pos.y < 60.0 and pos.x > 230.0:
			return "exit"
		_finish(false)
		return "hold"

	func _finish(ok: bool) -> void:
		print("physics pos=%s floor=%s goal=%s" % [player.position, player.is_on_floor(), goal])
		print("PHYSICS %s" % ("pass" if ok else "fail"))
		host.quit(0 if ok else 1)
