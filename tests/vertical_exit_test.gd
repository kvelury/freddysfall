extends SceneTree

## Teleports the player into each door sprite and checks the room transition
## lands them on the resolved platform.

func _initialize() -> void:
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var driver := Driver.new()
	driver.player = world.get_node("Player")
	driver.host = self
	world.add_child(driver)
	world.move_child(driver, 0)


class Driver extends Node:
	var player: Player
	var host: SceneTree
	var frames := 0
	var phase := "into_b"
	var data = null

	func _ready() -> void:
		data = host.root.get_node("WorldData")

	func _physics_process(_delta: float) -> void:
		frames += 1
		var room_id := String(host.root.get_node("GameState").current_room_id)
		match phase:
			"into_b":
				if room_id == "a" and player.input_enabled:
					_shove(Vector2(312, 40))
				elif room_id == "b" and player.input_enabled:
					phase = "into_c"
			"into_c":
				if room_id == "b" and player.input_enabled:
					_shove(_door_point("b", "down"))
				elif room_id == "c" and player.input_enabled:
					if not _at_landing("c", "up"):
						_finish(false)
						return
					phase = "into_d"
			"into_d":
				if room_id == "c" and player.input_enabled:
					_shove(_door_point("c", "down"))
				elif room_id == "d" and player.input_enabled:
					if not _at_landing("d", "up"):
						_finish(false)
						return
					phase = "back_c"
			"back_c":
				if room_id == "d" and player.input_enabled:
					_shove(_door_point("d", "up"))
				elif room_id == "c" and player.input_enabled:
					_finish(_at_landing("c", "down"))
					return
		if frames > 700:
			print("timed out in %s at %s room %s" % [phase, player.global_position, room_id])
			_finish(false)

	func _shove(spot: Vector2) -> void:
		player.exit_lock = 0.0
		player.global_position = spot
		player.velocity = Vector2.ZERO

	func _door_point(room_id: String, edge: String) -> Vector2:
		var info = data.get_room(room_id)
		var rect: Rect2i = info.exit_on(edge)["rect"]
		var pixel := Grid.cell_rect(rect)
		var center := Vector2(info.grid_pos) * Grid.SCREEN_SIZE + pixel.get_center()
		if edge == "up":
			center.y = Vector2(info.grid_pos).y * Grid.SCREEN_SIZE.y + 14.0
		elif edge == "down":
			center.y = Vector2(info.grid_pos).y * Grid.SCREEN_SIZE.y + info.pixel_size.y - 14.0
		return center

	func _at_landing(room_id: String, edge: String) -> bool:
		var info = data.get_room(room_id)
		var landing: Dictionary = info.vertical_landing(info.exit_on(edge)["rect"])
		var expected: Vector2 = Vector2(info.grid_pos) * Grid.SCREEN_SIZE + info.plant_position(landing["cell"])
		var delta := player.global_position - expected
		var ok := absf(delta.x) <= 2.0 and absf(delta.y) <= 2.0
		print(("ok   " if ok else "FAIL ") + "%s via %s at %s expected %s" % [room_id, edge, player.global_position, expected])
		return ok

	func _finish(ok: bool) -> void:
		print("VERTICAL %s" % ("pass" if ok else "fail"))
		host.quit(0 if ok else 1)
