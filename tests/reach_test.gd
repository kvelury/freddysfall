extends SceneTree

func _initialize() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	if cfg == null:
		print("FAIL movement.tres did not load")
		return false
	var passed := true
	passed = _feel(cfg) and passed
	passed = _room_a(cfg, data) and passed
	passed = _room_c(cfg, data) and passed
	passed = _links(data) and passed
	passed = _vertical(data) and passed
	passed = _room_d(cfg, data) and passed
	passed = _sensors(data) and passed
	passed = _camera() and passed
	print("RESULT %s" % ("pass" if passed else "fail"))
	return passed


func _feel(cfg: MovementConfig) -> bool:
	var floor_only: Array[Rect2] = [Rect2(0, 170, 800, 10)]
	var full := MovementSim.simulate_jump(cfg, floor_only, Vector2(40, 165), Vector2(cfg.run_speed, 0), 1.0, 90)
	var tap := MovementSim.simulate_jump(cfg, floor_only, Vector2(40, 165), Vector2(cfg.run_speed, 0), 1.0, 2)
	var rise := 170.0 - float(full["min_feet"])
	var tap_rise := 170.0 - float(tap["min_feet"])
	var dist := float(full["position"].x) - 40.0
	var ok := true
	ok = _check(rise >= 44.0 and rise <= 52.0, "full jump height %.1f px (about 4.8 cells)" % rise) and ok
	ok = _check(tap_rise < 20.0, "tap jump stays short (%.1f px)" % tap_rise) and ok
	ok = _check(dist >= 50.0 and dist <= 80.0, "running jump travels %.1f px" % dist) and ok
	return ok


func _room_a(cfg: MovementConfig, data) -> bool:
	var info = data.get_room("a")
	var rects := _pixels(info)
	var ok := true
	ok = _check(_has_rect(info, Rect2i(6, 13, 5, 1)), "left platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(21, 13, 5, 1)), "right platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(14, 9, 5, 1)), "middle platform rect") and ok
	ok = _check(_has_rect(info, Rect2i(23, 5, 9, 1)), "top platform rect") and ok
	ok = _check(_lands(cfg, rects, Vector2(25, 165), 1.0, 90, 130.0, 60.0, 110.0), "floor running jump reaches left platform") and ok
	ok = _check(not _lands(cfg, rects, Vector2(25, 165), 1.0, 2, 130.0, 60.0, 110.0), "tap from the floor misses the left platform") and ok
	ok = _check(_lands(cfg, rects, Vector2(100, 125), 1.0, 90, 90.0, 140.0, 190.0), "left platform reaches the middle") and ok
	ok = _check(not _lands(cfg, rects, Vector2(70, 125), 1.0, 90, 90.0, 140.0, 190.0), "jumping early from the left platform misses") and ok
	ok = _check(_lands(cfg, rects, Vector2(180, 85), 1.0, 90, 50.0, 230.0, 320.0), "middle platform reaches the exit ledge") and ok
	ok = _check(not _lands(cfg, rects, Vector2(150, 85), 1.0, 90, 50.0, 230.0, 320.0), "jumping early from the middle misses the exit ledge") and ok
	var b = data.get_room("b")
	var brects := _pixels(b)
	ok = _check(_lands(cfg, brects, Vector2(120, 165), 1.0, 90, 130.0, 160.0, 230.0), "room B floor reaches the low step") and ok
	ok = _check(_lands(cfg, brects, Vector2(175, 125), -1.0, 90, 90.0, 80.0, 150.0), "room B low step reaches the mid step") and ok
	ok = _check(_lands(cfg, brects, Vector2(95, 85), -1.0, 90, 50.0, 0.0, 70.0), "room B mid step reaches the entry ledge") and ok
	return ok


func _room_c(cfg: MovementConfig, data) -> bool:
	var info = data.get_room("c")
	var rects := _pixels(info)
	var ok := true
	ok = _check(_lands(cfg, rects, Vector2(270, 75), 1.0, 90, 120.0, 340.0, 480.0), "room C landing reaches the middle step") and ok
	ok = _check(_lands(cfg, rects, Vector2(450, 115), 1.0, 90, 150.0, 520.0, 630.0), "room C middle step reaches the far ledge") and ok
	ok = _check(_lands(cfg, rects, Vector2(150, 165), 1.0, 90, 150.0, 200.0, 320.0), "room C floor reaches the low step") and ok
	ok = _check(_lands(cfg, rects, Vector2(290, 145), 1.0, 90, 120.0, 340.0, 480.0), "room C low step reaches the middle") and ok
	ok = _check(_lands(cfg, rects, Vector2(350, 115), -1.0, 90, 80.0, 160.0, 300.0), "room C middle step reaches the landing") and ok
	var room := Room.new()
	room.build(info)
	var chunks := 0
	for child in room.get_children():
		if String(child.name).begins_with("Chunk_"):
			chunks += 1
	ok = _check(chunks == 2, "room C builds one chunk per screen (%d)" % chunks) and ok
	room.free()
	return ok


func _links(data) -> bool:
	var a = data.get_room("a")
	var b = data.get_room("b")
	var ok := true
	ok = _check(String(a.exit_on("right").get("dest_id", "")) == "b", "room A right exit leads to B") and ok
	ok = _check(String(b.exit_on("left").get("dest_id", "")) == "a", "room B left exit leads to A") and ok
	var into_b: Vector2i = b.stand_cell_for_entry("left")
	var back_to_a: Vector2i = a.stand_cell_for_entry("right")
	ok = _check(not b.is_solid(into_b.x, into_b.y) and b.is_solid(into_b.x, into_b.y + 1), "room B entry %s is a standable cell" % into_b) and ok
	ok = _check(not a.is_solid(back_to_a.x, back_to_a.y) and a.is_solid(back_to_a.x, back_to_a.y + 1), "room A return %s is a standable cell" % back_to_a) and ok
	var c = data.get_room("c")
	ok = _check(c.screens == Vector2i(2, 1), "room C spans two screens") and ok
	ok = _check(c.bounds_cells == Rect2i(0, 0, 64, 18), "room C bounds cover the whole room") and ok
	ok = _check(data.id_at(Vector2i(1, 1)) == "c" and data.id_at(Vector2i(2, 1)) == "c", "room C occupies both of its screens") and ok
	var down: Dictionary = b.exit_on("down")
	ok = _check(String(down.get("dest_id", "")) == "c", "room B bottom exit leads to C") and ok
	ok = _check(Vector2i(down.get("screen", Vector2i.ZERO)) == Vector2i(1, 0), "room B bottom exit sits on the second screen") and ok
	var into_c: Vector2i = c.stand_cell_for_rect(down.get("dest_rect", Rect2i()))
	ok = _check(not c.is_solid(into_c.x, into_c.y) and c.is_solid(into_c.x, into_c.y + 1), "room C entry %s is a standable cell" % into_c) and ok
	ok = _check(String(c.exit_on("up").get("dest_id", "")) == "b", "room C ceiling exit leads back to B") and ok
	return ok


func _vertical(data) -> bool:
	var b = data.get_room("b")
	var c = data.get_room("c")
	var ok := true
	var into_c: Dictionary = c.vertical_landing(c.exit_on("up")["rect"])
	ok = _landing(c, into_c, Vector2i(34, 11), "right", "room C from above") and ok
	var back_b: Dictionary = b.vertical_landing(b.exit_on("down")["rect"])
	ok = _landing(b, back_b, Vector2i(22, 12), "left", "room B from below") and ok
	ok = _check(int(back_b["right"]) == 0, "room B has no ground right of the pit") and ok
	var down: Dictionary = c.exit_on("down")
	var back_c: Dictionary = c.vertical_landing(down["rect"])
	ok = _landing(c, back_c, Vector2i(43, 16), "left", "room C from below") and ok
	ok = _check(int(back_c["left"]) > int(back_c["right"]), "room C floor exit has more ground on the left") and ok
	return ok


func _landing(info, landing: Dictionary, cell: Vector2i, side: String, label: String) -> bool:
	var ok := not landing.is_empty()
	ok = _check(ok, "%s finds a landing" % label) and ok
	if landing.is_empty():
		return false
	var got: Vector2i = landing["cell"]
	ok = _check(got == cell, "%s lands at %s (got %s, L%d R%d)" % [label, cell, got, int(landing["left"]), int(landing["right"])]) and ok
	ok = _check(String(landing["side"]) == side, "%s uses the wider side %s" % [label, landing["side"]]) and ok
	ok = _check(not info.is_solid(got.x, got.y) and info.is_solid(got.x, got.y + 1) and not info.is_solid(got.x, got.y - 1), "%s cell has space" % label) and ok
	ok = _check(info.drop_lift(got) >= 8.0, "%s drops onto the platform (%.0f px)" % [label, info.drop_lift(got)]) and ok
	return ok


func _room_d(cfg: MovementConfig, data) -> bool:
	var d = data.get_room("d")
	var c = data.get_room("c")
	var rects := _pixels(d)
	var ok := true
	ok = _check(d.screens == Vector2i(1, 1), "room D is one screen") and ok
	ok = _check(data.id_at(Vector2i(2, 2)) == "d", "room D sits under room C's right screen") and ok
	ok = _check(String(c.exit_on("down").get("dest_id", "")) == "d", "room C ground exit leads to D") and ok
	ok = _check(String(d.exit_on("up").get("dest_id", "")) == "c", "room D ceiling leads back to C") and ok
	var into_d: Dictionary = d.vertical_landing(d.exit_on("up")["rect"])
	ok = _landing(d, into_d, Vector2i(11, 7), "left", "room D from above") and ok
	ok = _check(int(into_d.get("left", 0)) > int(into_d.get("right", 0)), "room D has more ground on the left") and ok
	ok = _check(_has_rect(d, Rect2i(13, 4, 5, 1)), "room D return pad sits under the ceiling door") and ok
	var door: Rect2i = d.exit_on("up")["rect"]
	var sensor := Rect2(float(door.position.x * Grid.CELL), 0.0, float(door.size.x * Grid.CELL), Room.HALO_REACH)
	# The whole pad is under the opening, so a hop from either end touches the sprite.
	ok = _check(_enters(cfg, rects, Vector2(135, 35), 0.0, 90, sensor), "full jump from the left of the return pad enters the door") and ok
	ok = _check(_enters(cfg, rects, Vector2(175, 35), 0.0, 90, sensor), "full jump from the right of the return pad enters the door") and ok
	ok = _check(_enters(cfg, rects, Vector2(135, 35), 0.0, 2, sensor), "tap jump from the left of the return pad enters the door") and ok
	ok = _check(_enters(cfg, rects, Vector2(175, 35), 0.0, 2, sensor), "tap jump from the right of the return pad enters the door") and ok
	ok = _check(_enters(cfg, rects, Vector2(115, 75), 1.0, 90, sensor), "running jump from the landing platform enters the door") and ok
	return ok


func _sensors(data) -> bool:
	var ok := true
	var a = data.get_room("a")
	var b = data.get_room("b")
	var c = data.get_room("c")
	ok = _check(_sensor_size(a, "right") == Vector2(14, 20), "horizontal sensor stays a thin edge") and ok
	ok = _check(_sensor_size(b, "down") == Vector2(70, Room.HALO_REACH), "room B pit sensor covers the door sprite") and ok
	ok = _check(_sensor_size(c, "up") == Vector2(70, Room.HALO_REACH), "room C ceiling sensor covers the door sprite") and ok
	ok = _check(_sensor_size(c, "down") == Vector2(70, Room.HALO_REACH), "room C floor sensor covers the door sprite") and ok
	return ok


func _sensor_size(info, edge: String) -> Vector2:
	var room := Room.new()
	room.build(info)
	var size := Vector2.ZERO
	for child in room.get_children():
		if child is Area2D and String(child.get_meta("edge")) == edge:
			var shape := (child.get_child(0) as CollisionShape2D).shape as RectangleShape2D
			size = shape.size
			break
	room.free()
	return size


func _camera() -> bool:
	var ok := true
	var one := Grid.camera_focus(Vector2(320, 0), Vector2(320, 180), Vector2(400, 90))
	ok = _check(one == Vector2(480, 90), "one-screen room keeps the camera centered (%s)" % one) and ok
	var wide := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(900, 200))
	ok = _check(wide == Vector2(800, 270), "two-screen room clamps the camera (%s)" % wide) and ok
	var followed := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(600, 250))
	ok = _check(followed == Vector2(600, 270), "two-screen room follows within the span (%s)" % followed) and ok
	return ok


func _enters(cfg: MovementConfig, rects: Array, start: Vector2, input_x: float, hold: int, sensor: Rect2) -> bool:
	var pos := start
	var vel := Vector2(input_x * cfg.run_speed, 0.0)
	var grounded := true
	var coyote := cfg.coyote_time
	var buffer := 0.0
	var launched := false
	var cut := false
	var delta := 1.0 / 60.0
	var half := Vector2(5.0, 5.0)
	var out := {}
	for frame in 180:
		MovementSim.integrate(
			cfg, vel, grounded, coyote, buffer, launched, cut,
			input_x, frame == 0, frame < hold, delta, out
		)
		vel = out["velocity"]
		coyote = out["coyote"]
		buffer = out["buffer"]
		launched = out["launched"]
		cut = out["cut"]
		var resolved := MovementSim.resolve(pos, vel, rects, delta, half)
		pos = resolved["position"]
		vel = resolved["velocity"]
		grounded = resolved["grounded"]
		var body := Rect2(pos - half, half * 2.0)
		if body.intersects(sensor):
			return true
		if grounded and frame > 2:
			break
	print("  missed the door from %s, ended at %s" % [start, pos])
	return false


func _lands(cfg: MovementConfig, rects: Array, start: Vector2, input_x: float, hold: int, top: float, x_min: float, x_max: float) -> bool:
	var vel := Vector2(input_x * cfg.run_speed, 0.0)
	var result := MovementSim.simulate_jump(cfg, rects, start, vel, input_x, hold)
	if not result["landed"]:
		print("  no landing from %s -> %s" % [start, result["position"]])
		return false
	var floor: Rect2 = result["floor"]
	var pos: Vector2 = result["position"]
	var on_top := absf(floor.position.y - top) <= 0.1
	var over := pos.x + 5.0 > x_min and pos.x - 5.0 < x_max
	if not on_top or not over:
		print("  landed at %s on y=%.1f, wanted top %.1f within x %.1f-%.1f" % [pos, floor.position.y, top, x_min, x_max])
	return on_top and over


func _pixels(info) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for cell in info.solids:
		rects.append(Grid.cell_rect(cell))
	return rects


func _has_rect(info, expected: Rect2i) -> bool:
	for cell in info.solids:
		if cell == expected:
			return true
	print("  solids: ", info.solids)
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
