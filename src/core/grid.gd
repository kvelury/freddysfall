class_name Grid
extends RefCounted

const CELL := 10
const ROOM_CELLS := Vector2i(32, 18)
const ROOM_SIZE := Vector2(320, 180)


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(CELL)


static func world_to_cell(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / float(CELL)), floori(world.y / float(CELL)))


static func cell_center(cell: Vector2i) -> Vector2:
	return cell_to_world(cell) + Vector2(float(CELL) * 0.5, float(CELL) * 0.5)


static func cell_rect(cell_rect: Rect2i) -> Rect2:
	return Rect2(cell_to_world(cell_rect.position), Vector2(cell_rect.size) * float(CELL))
