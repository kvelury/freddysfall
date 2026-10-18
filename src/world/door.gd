class_name Door
extends RefCounted

## One opening in a room's outer wall, and the opening on the far side of it.

var edge := ""
## Local cells of the opening, one cell thick.
var rect := Rect2i()
## World screen cell the opening sits on.
var screen := Vector2i.ZERO
var dest_id := ""
var dest_rect := Rect2i()

## The slowest a body leaves an up door, in px/s. A body touching a ceiling
## door near the top of its jump would otherwise stall in the doorway.
const UP_BOOST := 180.0
## How far in from a door's plane a body's centre must be to be clear of the
## door's trigger: the door cell, the 4 px the trigger reaches beyond it, half
## the body, and a hair.
const CLEAR := 10.0 + 4.0 + 5.0 + 0.5


## True for an opening in a left or right wall, which runs up and down.
func is_side() -> bool:
	return edge == "left" or edge == "right"


## Room-local pixels that change rooms when the player touches them: the
## opening plus a little of the room beside it. The room tests the player's
## box against this and the reach solver tests paths against it, so they agree.
func trigger_rect() -> Rect2:
	var pixel := Grid.cell_rect(rect)
	match edge:
		"right":
			pixel.position.x -= 4.0
			pixel.size.x += 4.0
		"left":
			pixel.size.x += 4.0
		"up":
			pixel.size.y += 4.0
		"down":
			pixel.position.y -= 4.0
			pixel.size.y += 4.0
	return pixel


## Room-local pixels just inside this opening, clear of its trigger. For a
## side door it is the lowest row, so a body put there lands on the floor.
func doorway(room: RoomInfo) -> Vector2:
	var cell := float(Grid.CELL)
	var half := cell * 0.5
	var middle := (float(rect.position.x) + float(rect.size.x) * 0.5) * cell
	match edge:
		"left":
			return Vector2(CLEAR, float(rect.end.y) * cell - half)
		"right":
			return Vector2(room.pixel_size.x - CLEAR, float(rect.end.y) * cell - half)
		"up":
			return Vector2(middle, CLEAR)
	return Vector2(middle, room.pixel_size.y - CLEAR)


## A body that touched `door` in `source` at world pixels `position`, moving at
## `velocity`, as it appears in `dest`: the same place along the wall (kept
## inside the far door's span), pushed in past the far door's trigger so it
## does not touch it at once, with the same velocity. Going up, it leaves at
## least UP_BOOST. If a wall is in the way the push is shortened. Returns
## {"position": world pixels, "velocity": px/s}.
static func crossing(door: Door, dest: RoomInfo, position: Vector2, velocity: Vector2) -> Dictionary:
	var far := dest.door_by_rect(door.dest_rect)
	var origin := Vector2(dest.grid_pos) * Grid.SCREEN_SIZE
	var cell := float(Grid.CELL)
	var half := cell * 0.5
	var span := Grid.cell_rect(far.rect)
	span.position += origin
	var vel := velocity
	var pos := position
	for push in [CLEAR, cell + half, cell, half]:
		match door.edge:
			"right":
				pos = Vector2(origin.x + push, clampf(position.y, span.position.y + half, span.end.y - half))
			"left":
				pos = Vector2(origin.x + dest.pixel_size.x - push, clampf(position.y, span.position.y + half, span.end.y - half))
			"down":
				pos = Vector2(clampf(position.x, span.position.x + half, span.end.x - half), origin.y + push)
			"up":
				pos = Vector2(clampf(position.x, span.position.x + half, span.end.x - half), origin.y + dest.pixel_size.y - push)
		if not _walled(dest, pos - origin):
			break
	if door.edge == "up":
		vel.y = minf(vel.y, -UP_BOOST)
	return {"position": pos, "velocity": vel}


static func _walled(room: RoomInfo, local_center: Vector2) -> bool:
	var half := float(Grid.CELL) * 0.5
	var body := Rect2(local_center - Vector2(half, half), Vector2(half, half) * 2.0)
	for cell_rect in room.solids:
		if Grid.cell_rect(cell_rect).intersects(body):
			return true
	return false


static func opposite(edge_name: String) -> String:
	match edge_name:
		"left":
			return "right"
		"right":
			return "left"
		"up":
			return "down"
		"down":
			return "up"
	return edge_name


static func direction(edge_name: String) -> Vector2i:
	match edge_name:
		"left":
			return Vector2i(-1, 0)
		"right":
			return Vector2i(1, 0)
		"up":
			return Vector2i(0, -1)
		"down":
			return Vector2i(0, 1)
	return Vector2i.ZERO
