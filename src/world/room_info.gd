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
## Whether the room is meant to be a dead end the player cannot climb out of yet
## (`trap: allowed`). A way home that is missing is a warning here, not an error.
var traps_allowed := false


## Whether this is a save room: its id is `s` and a number (`s1`). Dying with no
## health sends the player back to the save room they last entered.
func is_save_room() -> bool:
	return is_save_id(id)


static func is_save_id(room_id: String) -> bool:
	return room_id.begins_with("s")


## The cell of the room's save machine, or (-1, -1) if it has none.
func save_cell() -> Vector2i:
	for def in entities:
		if def.type == "save":
			return def.cell
	return Vector2i(-1, -1)


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
