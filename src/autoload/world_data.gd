extends Node

var start_room := "a"
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
		rooms[info.id] = info
		_by_pos[info.grid_pos] = info.id
		pending.append(info)
	for info in pending:
		info.solids = _merge_solids(info.rows)
		info.exits = _parse_exits(info.rows, info.grid_pos)
		info.spawn_cell = _find_spawn(info.rows)
		info.no_imprint = _find_cells(info.rows, "~")


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
	var expected := Grid.ROOM_CELLS
	if rows.size() != expected.y:
		push_error("Room %s has %d rows, expected %d" % [room_id, rows.size(), expected.y])
	for y in rows.size():
		if rows[y].length() != expected.x:
			push_error("Room %s row %d has width %d, expected %d" % [room_id, y, rows[y].length(), expected.x])
	return rows


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
	var width := Grid.ROOM_CELLS.x
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


func _parse_exits(rows: Array[String], grid_pos: Vector2i) -> Array:
	var width := Grid.ROOM_CELLS.x
	var height := Grid.ROOM_CELLS.y
	var cells_by_edge := {"left": [], "right": [], "up": [], "down": []}
	for y in mini(height, rows.size()):
		var row := rows[y]
		for x in mini(width, row.length()):
			if row[x] != "X":
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
				push_error("Exit at %d,%d is not on a room edge" % [x, y])
				continue
			cells_by_edge[edge].append(Vector2i(x, y))
	var exits: Array = []
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
					split = cur.y != prev.y + 1 or cur.x != prev.x
				else:
					split = cur.x != prev.x + 1 or cur.y != prev.y
			if split:
				var first: Vector2i = cells[group_start]
				var count := i - group_start
				var rect := Rect2i(first.x, first.y, 1, count) if vertical else Rect2i(first.x, first.y, count, 1)
				var dest_pos := grid_pos + _edge_dir(edge)
				exits.append({
					"edge": edge,
					"rect": rect,
					"dest_id": id_at(dest_pos),
				})
				group_start = i
	return exits


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
	var spawn_cell := Vector2i(2, 16)
	var rows: Array[String] = []
	var solids: Array[Rect2i] = []
	var exits: Array = []
	var no_imprint: Array[Vector2i] = []

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
