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


## True for an opening in a left or right wall, which runs up and down.
func is_side() -> bool:
	return edge == "left" or edge == "right"


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
