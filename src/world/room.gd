class_name Room
extends Node2D

var info: RoomInfo
## Whether touching a door changes rooms. Off while a transition is running.
var exits_active := false


func build(room_info: RoomInfo) -> void:
	info = room_info
	# One drawable chunk per screen. Godot culls a chunk whose rect is
	# outside the camera, so a long room costs the same as the screens in view.
	var screens: Vector2i = info.screens
	for sy in screens.y:
		for sx in screens.x:
			var local_rects := _rects_in_screen(info.solids, sx, sy)
			if local_rects.is_empty():
				continue
			var chunk := RoomChunk.new()
			chunk.name = "Chunk_%d_%d" % [sx, sy]
			chunk.position = Vector2(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y) * float(Grid.CELL)
			chunk.rects = local_rects
			add_child(chunk)
	for ex in info.exits:
		_add_halo(ex)


func set_exits_active(active: bool) -> void:
	exits_active = active


## The door that a body at `body` (world pixels) is touching, or null.
func touched_door(body: Rect2) -> Door:
	if not exits_active:
		return null
	for door in info.exits:
		var trigger := door.trigger_rect()
		if Rect2(trigger.position + position, trigger.size).intersects(body):
			return door
	return null


## The room's solids as pixel rects in world space, for the player to collide
## with.
func world_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for cell_rect in info.solids:
		var pixel := Grid.cell_rect(cell_rect)
		out.append(Rect2(pixel.position + position, pixel.size))
	return out


func _rects_in_screen(solids: Array[Rect2i], sx: int, sy: int) -> Array[Rect2i]:
	var screen := Rect2i(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y, Grid.SCREEN_CELLS.x, Grid.SCREEN_CELLS.y)
	var out: Array[Rect2i] = []
	for cell_rect in solids:
		if not screen.intersects(cell_rect):
			continue
		var clipped: Rect2i = screen.intersection(cell_rect)
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		out.append(Rect2i(clipped.position - screen.position, clipped.size))
	return out


func _add_halo(ex: Door) -> void:
	var pixel: Rect2 = Grid.cell_rect(ex.rect)
	var halo := ExitHalo.new()
	match ex.edge:
		"right":
			halo.position = Vector2(pixel.end.x, pixel.get_center().y)
			halo.direction = Vector2.LEFT
		"left":
			halo.position = Vector2(pixel.position.x, pixel.get_center().y)
			halo.direction = Vector2.RIGHT
		"up":
			halo.position = Vector2(pixel.get_center().x, pixel.position.y)
			halo.direction = Vector2.DOWN
		"down":
			halo.position = Vector2(pixel.get_center().x, pixel.end.y)
			halo.direction = Vector2.UP
	halo.z_index = 1
	add_child(halo)


class RoomChunk extends Node2D:
	var rects: Array[Rect2i] = []

	func _draw() -> void:
		for cell_rect in rects:
			draw_rect(Grid.cell_rect(cell_rect), Color.WHITE, true)
