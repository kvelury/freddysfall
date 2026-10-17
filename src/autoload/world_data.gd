extends Node

var start_room := "1"
var rooms := {}
var _by_pos := {}
var _loaded := false


func _ready() -> void:
	ensure_loaded()


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string("res://data/world.json")
	var data = JSON.parse_string(text)
	if data == null:
		push_error("Failed to parse res://data/world.json")
		return
	start_room = String(data["start_room"])
	var pending: Array[RoomInfo] = []
	for entry in data["rooms"]:
		var info := RoomInfo.new()
		info.id = String(entry["id"])
		var pos: Array = entry["grid_pos"]
		info.grid_pos = Vector2i(int(pos[0]), int(pos[1]))
		info.rows = _read_rows(String(entry["file"]), info.id)
		_apply_size(info)
		rooms[info.id] = info
		for cell in info.occupied_cells():
			if _by_pos.has(cell):
				push_error("Room %s overlaps %s at screen %s" % [info.id, String(_by_pos[cell]), cell])
			else:
				_by_pos[cell] = info.id
		pending.append(info)
	for info in pending:
		info.solids = _merge_solids(info.rows)
		info.exits = _parse_exits(info)
		info.spawn_cell = _find_spawn(info.rows)
		info.no_imprint = _find_cells(info.rows, "~")
	_link_exits(pending)


func get_room(id: String) -> RoomInfo:
	ensure_loaded()
	return rooms[id]


func id_at(grid_pos: Vector2i) -> String:
	return String(_by_pos.get(grid_pos, ""))


func _read_rows(path: String, room_id: String) -> Array[String]:
	var text := FileAccess.get_file_as_string(path)
	var rows: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.replace("\r", "")
		if line.is_empty():
			continue
		rows.append(line)
	if rows.is_empty():
		push_error("Room %s is empty" % room_id)
		return rows
	var width := rows[0].length()
	var height := rows.size()
	var screen := Grid.SCREEN_CELLS
	if width % screen.x != 0 or height % screen.y != 0:
		push_error("Room %s is %d x %d cells; size must be a whole number of %d x %d screens" % [room_id, width, height, screen.x, screen.y])
	for y in rows.size():
		if rows[y].length() != width:
			push_error("Room %s row %d has width %d, expected %d" % [room_id, y, rows[y].length(), width])
	return rows


func _apply_size(info: RoomInfo) -> void:
	if info.rows.is_empty():
		info.cell_size = Grid.SCREEN_CELLS
	else:
		info.cell_size = Vector2i(info.rows[0].length(), info.rows.size())
	var screen := Grid.SCREEN_CELLS
	info.screens = Vector2i(maxi(1, int(info.cell_size.x / screen.x)), maxi(1, int(info.cell_size.y / screen.y)))
	info.pixel_size = Vector2(info.cell_size) * float(Grid.CELL)
	# Imprint platforms must fit inside the whole room, not just the screen
	# the camera happens to be showing.
	info.bounds_cells = Rect2i(Vector2i.ZERO, info.cell_size)


func _find_spawn(rows: Array[String]) -> Vector2i:
	for y in rows.size():
		var x := rows[y].find("P")
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(2, 16)


func _find_cells(rows: Array[String], glyph: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in rows.size():
		var row := rows[y]
		for x in row.length():
			if row[x] == glyph:
				cells.append(Vector2i(x, y))
	return cells


func _merge_solids(rows: Array[String]) -> Array[Rect2i]:
	if rows.is_empty():
		return []
	var width := rows[0].length()
	var runs: Array[Vector3i] = []
	for y in rows.size():
		var row := rows[y]
		var x := 0
		while x < width and x < row.length():
			if row[x] == "#":
				var start := x
				while x < width and x < row.length() and row[x] == "#":
					x += 1
				runs.append(Vector3i(start, y, x - start))
			else:
				x += 1
	var used: Array[bool] = []
	used.resize(runs.size())
	used.fill(false)
	var rects: Array[Rect2i] = []
	for i in runs.size():
		if used[i]:
			continue
		var run := runs[i]
		var height := 1
		while true:
			var nxt := -1
			for j in runs.size():
				if used[j]:
					continue
				var other := runs[j]
				if other.y == run.y + height and other.x == run.x and other.z == run.z:
					nxt = j
					break
			if nxt == -1:
				break
			used[nxt] = true
			height += 1
		used[i] = true
		rects.append(Rect2i(run.x, run.y, run.z, height))
	return rects


func _parse_exits(info: RoomInfo) -> Array:
	var rows := info.rows
	if rows.is_empty():
		return []
	var width := rows[0].length()
	var height := rows.size()
	var cells_by_edge := {"left": [], "right": [], "up": [], "down": []}
	for y in height:
		var row := rows[y]
		for x in mini(width, row.length()):
			if row[x] != "X":
				continue
			var on_x := x == 0 or x == width - 1
			var on_y := y == 0 or y == height - 1
			if on_x and on_y:
				push_error("Room %s exit at %d,%d sits on a corner" % [info.id, x, y])
				continue
			var edge := ""
			if x == 0:
				edge = "left"
			elif x == width - 1:
				edge = "right"
			elif y == 0:
				edge = "up"
			elif y == height - 1:
				edge = "down"
			else:
				push_error("Room %s exit at %d,%d is not on the room edge" % [info.id, x, y])
				continue
			cells_by_edge[edge].append(Vector2i(x, y))
	var exits: Array = []
	var screen := Grid.SCREEN_CELLS
	for edge in ["left", "right", "up", "down"]:
		var cells: Array = cells_by_edge[edge]
		if cells.is_empty():
			continue
		var vertical: bool = String(edge) == "left" or String(edge) == "right"
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if vertical:
				return a.y < b.y
			return a.x < b.x
		)
		var group_start := 0
		for i in range(1, cells.size() + 1):
			var split := i == cells.size()
			if not split:
				var prev: Vector2i = cells[i - 1]
				var cur: Vector2i = cells[i]
				if vertical:
					var crossed_row := int(cur.y / screen.y) != int(prev.y / screen.y)
					split = cur.y != prev.y + 1 or cur.x != prev.x or crossed_row
				else:
					var crossed_col := int(cur.x / screen.x) != int(prev.x / screen.x)
					split = cur.x != prev.x + 1 or cur.y != prev.y or crossed_col
			if split:
				var first: Vector2i = cells[group_start]
				var count := i - group_start
				var rect := Rect2i(first.x, first.y, 1, count) if vertical else Rect2i(first.x, first.y, count, 1)
				var screen_cell := _screen_cell(info, rect, edge)
				exits.append({
					"edge": edge,
					"rect": rect,
					"screen": screen_cell,
					"dest_id": id_at(screen_cell + _edge_dir(edge)),
					"dest_rect": Rect2i(),
				})
				group_start = i
	return exits


func _screen_cell(info: RoomInfo, rect: Rect2i, edge: String) -> Vector2i:
	var screen := Grid.SCREEN_CELLS
	match edge:
		"left":
			return info.grid_pos + Vector2i(0, int(rect.position.y / screen.y))
		"right":
			return info.grid_pos + Vector2i(info.screens.x - 1, int(rect.position.y / screen.y))
		"up":
			return info.grid_pos + Vector2i(int(rect.position.x / screen.x), 0)
		"down":
			return info.grid_pos + Vector2i(int(rect.position.x / screen.x), info.screens.y - 1)
	return info.grid_pos


func _link_exits(pending: Array[RoomInfo]) -> void:
	for info in pending:
		for ex in info.exits:
			var dest_id := String(ex["dest_id"])
			if dest_id.is_empty():
				continue
			var dest: RoomInfo = rooms[dest_id]
			var matches: Array = []
			var span := _world_span(info, ex)
			for other in dest.exits:
				if String(other["edge"]) != _opposite(String(ex["edge"])):
					continue
				if Vector2i(other["screen"]) != Vector2i(ex["screen"]) + _edge_dir(String(ex["edge"])):
					continue
				if _spans_overlap(span, _world_span(dest, other)):
					matches.append(other)
			if matches.size() != 1:
				push_error("Room %s %s exit at %s has %d matching doors in %s" % [info.id, String(ex["edge"]), ex["rect"], matches.size(), dest_id])
				ex["dest_id"] = ""
				continue
			ex["dest_rect"] = matches[0]["rect"]


func _world_span(info: RoomInfo, ex: Dictionary) -> Vector2i:
	var rect: Rect2i = ex["rect"]
	var origin := info.grid_pos * Grid.SCREEN_CELLS
	var vertical: bool = String(ex["edge"]) == "left" or String(ex["edge"]) == "right"
	if vertical:
		var y0 := origin.y + rect.position.y
		return Vector2i(y0, y0 + rect.size.y)
	var x0 := origin.x + rect.position.x
	return Vector2i(x0, x0 + rect.size.x)


func _spans_overlap(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.y and b.x < a.y


func _opposite(edge: String) -> String:
	match edge:
		"left":
			return "right"
		"right":
			return "left"
		"up":
			return "down"
		"down":
			return "up"
	return edge


func _edge_dir(edge: String) -> Vector2i:
	match edge:
		"left":
			return Vector2i(-1, 0)
		"right":
			return Vector2i(1, 0)
		"up":
			return Vector2i(0, -1)
		"down":
			return Vector2i(0, 1)
	return Vector2i.ZERO


class RoomInfo extends RefCounted:
	var id := ""
	var grid_pos := Vector2i.ZERO
	var screens := Vector2i.ONE
	var cell_size := Vector2i(32, 18)
	var pixel_size := Vector2(320, 180)
	## Local cells an imprint platform must lie fully inside.
	var bounds_cells := Rect2i(0, 0, 32, 18)
	var spawn_cell := Vector2i(2, 16)
	var rows: Array[String] = []
	var solids: Array[Rect2i] = []
	var exits: Array = []
	var no_imprint: Array[Vector2i] = []

	func occupied_cells() -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for sy in screens.y:
			for sx in screens.x:
				cells.append(grid_pos + Vector2i(sx, sy))
		return cells

	func is_solid(x: int, y: int) -> bool:
		if y < 0 or y >= rows.size():
			return true
		var row := rows[y]
		if x < 0 or x >= row.length():
			return true
		return row[x] == "#"

	func exit_on(edge: String) -> Dictionary:
		for ex in exits:
			if String(ex["edge"]) == edge:
				return ex
		return {}

	func stand_cell_for_entry(edge: String) -> Vector2i:
		var ex := exit_on(edge)
		if ex.is_empty():
			return spawn_cell
		return _stand_on(ex)

	func stand_cell_for_rect(rect: Rect2i) -> Vector2i:
		for ex in exits:
			if ex["rect"] == rect:
				return _stand_on(ex)
		return spawn_cell

	func _stand_on(ex: Dictionary) -> Vector2i:
		var edge := String(ex["edge"])
		var gap: Rect2i = ex["rect"]
		if edge == "left" or edge == "right":
			var row := gap.position.y + gap.size.y - 1
			var col := gap.position.x
			var step_dir := 1 if edge == "left" else -1
			for step in range(2, 8):
				var c := col + step_dir * step
				if not is_solid(c, row) and is_solid(c, row + 1):
					return Vector2i(c, row)
		else:
			var col := gap.position.x + int(gap.size.x / 2.0)
			var row := gap.position.y
			var step_dir := 1 if edge == "up" else -1
			for step in range(2, 8):
				var r := row + step_dir * step
				if not is_solid(col, r) and is_solid(col, r + 1):
					return Vector2i(col, r)
		return spawn_cell
