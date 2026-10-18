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
	passed = _loader() and passed
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
	var info = data.get_room("1")
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
	var b: RoomInfo = data.get_room("2")
	var brects := _pixels(b)
	ok = _check(_lands(cfg, brects, Vector2(120, 165), 1.0, 90, 130.0, 160.0, 230.0), "room 2 floor reaches the low step") and ok
	ok = _check(_lands(cfg, brects, Vector2(175, 125), -1.0, 90, 90.0, 80.0, 150.0), "room 2 low step reaches the mid step") and ok
	ok = _check(_lands(cfg, brects, Vector2(95, 85), -1.0, 90, 50.0, 0.0, 70.0), "room 2 mid step reaches the entry ledge") and ok
	return ok


func _room_c(cfg: MovementConfig, data) -> bool:
	var info = data.get_room("3")
	var rects := _pixels(info)
	var ok := true
	ok = _check(_lands(cfg, rects, Vector2(270, 75), 1.0, 90, 120.0, 340.0, 480.0), "room 3 landing reaches the middle step") and ok
	ok = _check(_lands(cfg, rects, Vector2(450, 115), 1.0, 90, 150.0, 520.0, 630.0), "room 3 middle step reaches the far ledge") and ok
	ok = _check(_lands(cfg, rects, Vector2(150, 165), 1.0, 90, 150.0, 200.0, 320.0), "room 3 floor reaches the low step") and ok
	ok = _check(_lands(cfg, rects, Vector2(290, 145), 1.0, 90, 120.0, 340.0, 480.0), "room 3 low step reaches the middle") and ok
	ok = _check(_lands(cfg, rects, Vector2(350, 115), -1.0, 90, 80.0, 160.0, 300.0), "room 3 middle step reaches the landing") and ok
	var room := Room.new()
	room.build(info)
	var chunks := 0
	for child in room.get_children():
		if String(child.name).begins_with("Chunk_"):
			chunks += 1
	ok = _check(chunks == 2, "room 3 builds one chunk per screen (%d)" % chunks) and ok
	room.free()
	return ok


func _links(data) -> bool:
	var a: RoomInfo = data.get_room("1")
	var b: RoomInfo = data.get_room("2")
	var ok := true
	ok = _check(a.exit_on("right").dest_id == "2", "room 1 right exit leads to 2") and ok
	ok = _check(b.exit_on("left").dest_id == "1", "room 2 left exit leads to 1") and ok
	var into_b: Vector2i = b.stand_cell_for_entry("left")
	var back_to_a: Vector2i = a.stand_cell_for_entry("right")
	ok = _check(not b.is_solid(into_b.x, into_b.y) and b.is_solid(into_b.x, into_b.y + 1), "room 2 entry %s is a standable cell" % into_b) and ok
	ok = _check(not a.is_solid(back_to_a.x, back_to_a.y) and a.is_solid(back_to_a.x, back_to_a.y + 1), "room 1 return %s is a standable cell" % back_to_a) and ok
	var c: RoomInfo = data.get_room("3")
	ok = _check(c.screens == Vector2i(2, 1), "room 3 spans two screens") and ok
	ok = _check(c.bounds_cells == Rect2i(0, 0, 64, 18), "room 3 bounds cover the whole room") and ok
	ok = _check(data.id_at(Vector2i(2, 0)) == "3" and data.id_at(Vector2i(3, 0)) == "3", "room 3 occupies both of its screens") and ok
	var side := b.exit_on("right")
	var side_rect := side.rect
	ok = _check(b.exit_on("down") == null, "room 2 floor stays solid") and ok
	ok = _check(side.dest_id == "3", "room 2 floor exit leads to 3") and ok
	ok = _check(side_rect.position.y == 15 and side_rect.size == Vector2i(1, 2), "room 2 exit is a floor-level side door (%s)" % side_rect) and ok
	var into_c: Vector2i = c.stand_cell_for_rect(side.dest_rect)
	ok = _check(not c.is_solid(into_c.x, into_c.y) and c.is_solid(into_c.x, into_c.y + 1), "room 3 entry %s is a standable cell" % into_c) and ok
	var back := c.exit_on("left")
	var back_rect := back.rect
	ok = _check(c.exit_on("up") == null, "room 3 ceiling stays solid") and ok
	ok = _check(back.dest_id == "2", "room 3 side entrance leads back to 2") and ok
	ok = _check(back_rect.position.y == 15 and back_rect.size == Vector2i(1, 2), "room 3 entrance is a floor-level side door (%s)" % back_rect) and ok
	return ok


## Builds worlds from strings so every way a room file can be wrong is checked
## without touching the disk.
func _loader() -> bool:
	var ok := true
	var clean := _world([_entry("1", Vector2i(0, 0), _box())])
	ok = _check(clean["errors"].is_empty(), "a plain box loads clean %s" % [clean["errors"]]) and ok

	var bad_glyph := _world([_entry("1", Vector2i(0, 0), _box({Vector2i(5, 5): "?"}))])
	ok = _check(_has_error(bad_glyph["errors"], "not a known glyph"), "an unknown glyph is an error") and ok

	var open_edge := _world([_entry("1", Vector2i(0, 0), _box({Vector2i(0, 5): "."}))])
	ok = _check(_has_error(open_edge["errors"], "outer wall must be"), "an open edge cell is an error") and ok

	var open_row := {}
	for x in range(1, 31):
		open_row[Vector2i(x, 0)] = "."
	var many := _world([_entry("1", Vector2i(0, 0), _box(open_row))])
	ok = _check(many["errors"].size() == RoomParser.MAX_PER_KIND + 1 and _has_error(many["errors"], "more like that"), "a whole open wall is capped (%d lines)" % many["errors"].size()) and ok

	var wrong_size := _world([_entry("1", Vector2i(0, 0), _box().replace("\n", "#\n"))])
	ok = _check(_has_error(wrong_size["errors"], "whole number of"), "a room that is not whole screens is an error") and ok

	var no_spawn := _world([_entry("1", Vector2i(0, 0), _box({}, false))])
	ok = _check(_has_error(no_spawn["errors"], "has no P"), "the start room needs a P") and ok

	var no_start := _world([_entry("1", Vector2i(0, 0), _box())], "9")
	ok = _check(_has_error(no_start["errors"], "not in the world"), "an unlisted start room is an error") and ok

	var twice := _world([_entry("1", Vector2i(0, 0), _box()), _entry("1", Vector2i(1, 0), _box())])
	ok = _check(_has_error(twice["errors"], "listed twice"), "a repeated room id is an error") and ok

	var overlap := _world([_entry("1", Vector2i(0, 0), _box()), _entry("2", Vector2i(0, 0), _box({}, false))])
	ok = _check(_has_error(overlap["errors"], "overlaps"), "two rooms on one screen is an error") and ok

	var door := {Vector2i(31, 5): "X", Vector2i(31, 6): "X"}
	var dead_end := _world([_entry("1", Vector2i(0, 0), _box(door))])
	var lone: RoomInfo = dead_end["rooms"]["1"]
	ok = _check(dead_end["errors"].is_empty(), "a door to nowhere is not an error %s" % [dead_end["errors"]]) and ok
	ok = _check(lone.exits.is_empty() and lone.sealed == [Rect2i(31, 5, 1, 2)], "a door to nowhere is sealed (%s)" % [lone.sealed]) and ok
	ok = _check(lone.is_solid(31, 5) and lone.is_solid(31, 6), "a sealed door is solid") and ok
	ok = _check(_covers(lone.solids, Vector2i(31, 5)), "a sealed door is in the collision rects") and ok

	var left_door := {Vector2i(0, 5): "X", Vector2i(0, 6): "X"}
	var paired := _world([_entry("1", Vector2i(0, 0), _box(door)), _entry("2", Vector2i(1, 0), _box(left_door, false))])
	var first: RoomInfo = paired["rooms"]["1"]
	ok = _check(paired["errors"].is_empty() and first.exit_on("right").dest_id == "2", "facing doors pair up %s" % [paired["errors"]]) and ok
	ok = _check(first.exit_on("right").dest_rect == Rect2i(0, 5, 1, 2), "a door knows the rect of the door it meets") and ok

	var unmatched := _world([_entry("1", Vector2i(0, 0), _box(door)), _entry("2", Vector2i(1, 0), _box({}, false))])
	var stuck: RoomInfo = unmatched["rooms"]["1"]
	ok = _check(_has_error(unmatched["errors"], "0 matching doors"), "a door facing a wall is an error") and ok
	ok = _check(stuck.exits.is_empty() and stuck.is_solid(31, 5), "a door facing a wall is sealed") and ok
	return ok


## A 32 x 18 room with a wall around it. `cells` overrides single cells.
func _box(cells: Dictionary = {}, spawn := true) -> String:
	var lines: Array[String] = []
	for y in 18:
		var line := ""
		for x in 32:
			var glyph := "#" if x == 0 or y == 0 or x == 31 or y == 17 else "."
			if spawn and x == 2 and y == 16:
				glyph = "P"
			line += String(cells.get(Vector2i(x, y), glyph))
		lines.append(line)
	return "\n".join(lines)


func _entry(id: String, pos: Vector2i, text: String) -> Dictionary:
	return {"id": id, "grid_pos": pos, "text": text}


func _world(entries: Array, start := "1") -> Dictionary:
	var errors: Array[String] = []
	var built := RoomParser.build(entries, start, errors)
	built["errors"] = errors
	return built


func _has_error(errors: Array, fragment: String) -> bool:
	for message in errors:
		if String(message).contains(fragment):
			return true
	print("  no error containing '%s' in %s" % [fragment, errors])
	return false


func _covers(rects: Array[Rect2i], cell: Vector2i) -> bool:
	for rect in rects:
		if rect.has_point(cell):
			return true
	return false


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


func _pixels(info: RoomInfo) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for cell in info.solids:
		rects.append(Grid.cell_rect(cell))
	return rects


func _has_rect(info: RoomInfo, expected: Rect2i) -> bool:
	for cell in info.solids:
		if cell == expected:
			return true
	print("  solids: ", info.solids)
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
