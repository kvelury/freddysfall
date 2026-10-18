class_name RoomInfo
extends RefCounted

var id := ""
var grid_pos := Vector2i.ZERO
var screens := Vector2i.ONE
var cell_size := Vector2i(32, 18)
var pixel_size := Vector2(320, 180)
## Local cells an imprint platform must lie fully inside.
var bounds_cells := Rect2i(0, 0, 32, 18)
var has_spawn := false
var spawn_cell := Vector2i(2, 16)
## The room as loaded. Openings that lead nowhere have been sealed to solid.
var rows: Array[String] = []
var solids: Array[Rect2i] = []
var exits: Array[Door] = []
## Openings the loader closed because nothing was on the other side.
var sealed: Array[Rect2i] = []
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
	return Tiles.has_flag(row[x], "solid")


func exit_on(edge: String) -> Door:
	for door in exits:
		if door.edge == edge:
			return door
	return null


func stand_cell_for_entry(edge: String) -> Vector2i:
	var door := exit_on(edge)
	if door == null:
		return spawn_cell
	return _stand_on(door)


func stand_cell_for_rect(rect: Rect2i) -> Vector2i:
	for door in exits:
		if door.rect == rect:
			return _stand_on(door)
	return spawn_cell


func _stand_on(door: Door) -> Vector2i:
	var gap := door.rect
	if door.is_side():
		var row := gap.position.y + gap.size.y - 1
		var col := gap.position.x
		var step_dir := 1 if door.edge == "left" else -1
		for step in range(2, 8):
			var c := col + step_dir * step
			if not is_solid(c, row) and is_solid(c, row + 1):
				return Vector2i(c, row)
	else:
		var col := gap.position.x + int(gap.size.x / 2.0)
		var row := gap.position.y
		var step_dir := 1 if door.edge == "up" else -1
		for step in range(2, 8):
			var r := row + step_dir * step
			if not is_solid(col, r) and is_solid(col, r + 1):
				return Vector2i(col, r)
	return spawn_cell
