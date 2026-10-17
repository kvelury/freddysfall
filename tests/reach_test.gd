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
	ok = _check(data.id_at(Vector2i(2, 0)) == "c" and data.id_at(Vector2i(3, 0)) == "c", "room C occupies both of its screens") and ok
	var side: Dictionary = b.exit_on("right")
	var side_rect: Rect2i = side.get("rect", Rect2i())
	ok = _check(b.exit_on("down").is_empty(), "room B floor stays solid") and ok
	ok = _check(String(side.get("dest_id", "")) == "c", "room B floor exit leads to C") and ok
	ok = _check(side_rect.position.y == 15 and side_rect.size == Vector2i(1, 2), "room B exit is a floor-level side door (%s)" % side_rect) and ok
	var into_c: Vector2i = c.stand_cell_for_rect(side.get("dest_rect", Rect2i()))
	ok = _check(not c.is_solid(into_c.x, into_c.y) and c.is_solid(into_c.x, into_c.y + 1), "room C entry %s is a standable cell" % into_c) and ok
	var back: Dictionary = c.exit_on("left")
	var back_rect: Rect2i = back.get("rect", Rect2i())
	ok = _check(c.exit_on("up").is_empty(), "room C ceiling stays solid") and ok
	ok = _check(String(back.get("dest_id", "")) == "b", "room C side entrance leads back to B") and ok
	ok = _check(back_rect.position.y == 15 and back_rect.size == Vector2i(1, 2), "room C entrance is a floor-level side door (%s)" % back_rect) and ok
	return ok


func _camera() -> bool:
	var ok := true
	var one := Grid.camera_focus(Vector2(320, 0), Vector2(320, 180), Vector2(400, 90))
	ok = _check(one == Vector2(480, 90), "one-screen room keeps the camera centered (%s)" % one) and ok
	var wide := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(900, 200))
	ok = _check(wide == Vector2(800, 270), "two-screen room clamps the camera (%s)" % wide) and ok
	var followed := Grid.camera_focus(Vector2(320, 180), Vector2(640, 180), Vector2(600, 250))
	ok = _check(followed == Vector2(600, 270), "two-screen room follows within the span (%s)" % followed) and ok
	return ok


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
