class_name Grid
extends RefCounted

const CELL := 10
## One screen of the viewport. A room is one or more of these, edge to edge.
const SCREEN_CELLS := Vector2i(32, 18)
const SCREEN_SIZE := Vector2(320, 180)


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(CELL)


static func world_to_cell(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / float(CELL)), floori(world.y / float(CELL)))


static func cell_center(cell: Vector2i) -> Vector2:
	return cell_to_world(cell) + Vector2(float(CELL) * 0.5, float(CELL) * 0.5)


static func cell_rect(cell_rect: Rect2i) -> Rect2:
	return Rect2(cell_to_world(cell_rect.position), Vector2(cell_rect.size) * float(CELL))


## Where the camera sits to show `focus`, clamped inside a room.
## A room the size of one screen never scrolls. Larger rooms follow the
## focus and stop at the room edge. The result is whole pixels so the
## integer-scaled view does not shimmer while the camera moves.
static func camera_focus(room_origin: Vector2, room_size: Vector2, focus: Vector2) -> Vector2:
	var half := SCREEN_SIZE * 0.5
	var cam := focus
	if room_size.x <= SCREEN_SIZE.x:
		cam.x = room_origin.x + room_size.x * 0.5
	else:
		cam.x = clampf(focus.x, room_origin.x + half.x, room_origin.x + room_size.x - half.x)
	if room_size.y <= SCREEN_SIZE.y:
		cam.y = room_origin.y + room_size.y * 0.5
	else:
		cam.y = clampf(focus.y, room_origin.y + half.y, room_origin.y + room_size.y - half.y)
	return cam.round()
