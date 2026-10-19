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
## Cells that kill on touch.
var hazards: Array[Vector2i] = []
## The room's legend: glyph -> EntityDef. Only things drawn in the room are in
## `entities`, in legend order, with their cells.
var legend := {}
var entities: Array[EntityDef] = []
## What has to be true before the room's doors work, a key of ExitRules.RULES.
var exit_rule := "open"


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


## Room-local pixels where the player is put when a room is started in
## directly, not entered through a door: on its P, or else just inside its
## first door, to fall from there.
func start_position() -> Vector2:
	if has_spawn or exits.is_empty():
		return Grid.cell_center(spawn_cell)
	return exits[0].doorway(self)


func exit_on(edge: String) -> Door:
	for door in exits:
		if door.edge == edge:
			return door
	return null


func door_by_rect(rect: Rect2i) -> Door:
	for door in exits:
		if door.rect == rect:
			return door
	return null


func is_no_imprint(x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return false
	var row := rows[y]
	if x < 0 or x >= row.length():
		return false
	return Tiles.has_flag(row[x], "no_imprint")


func is_hazard(x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return false
	var row := rows[y]
	if x < 0 or x >= row.length():
		return false
	return Tiles.has_flag(row[x], "hazard")
