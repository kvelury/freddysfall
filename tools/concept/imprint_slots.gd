class_name ConceptSlots
extends RefCounted

## CONCEPT ONLY. The fixed places an Imprint may go, relative to Freddy.
## Offsets are (cells forward, rows down) to the anchor block, the one nearest
## Freddy that lasts longest; the rest of the platform extends away from him.
## Row +1 is the first row wholly under his feet. Facing left mirrors it.

const NEAR := "near"
const FAR := "far"
const DIRS := ["fwd", "upfwd", "up", "downfwd", "down"]
const SLOTS := {
	"fwd": {"near": Vector2i(1, 1), "far": Vector2i(4, 1)},
	"upfwd": {"near": Vector2i(2, -1), "far": Vector2i(4, -3)},
	"up": {"near": Vector2i(1, -3), "far": Vector2i(0, -5)},
	"downfwd": {"near": Vector2i(2, 2), "far": Vector2i(4, 4)},
	"down": {"near": Vector2i(0, 1), "far": Vector2i(0, 4)},
}
## Which way each direction points, facing right, for the arrow glyphs.
const ARROWS := {
	"fwd": Vector2(1, 0),
	"upfwd": Vector2(1, -1),
	"up": Vector2(0, -1),
	"downfwd": Vector2(1, 1),
	"down": Vector2(0, 1),
}


## Freddy's reference cell in room cells: his centre column, and the row just
## above the first row wholly below his feet.
static func ref_cell(local_pos: Vector2) -> Vector2i:
	var feet_row := ceili((local_pos.y + MovementSim.HALF.y) / float(Grid.CELL) - 0.001)
	return Vector2i(floori(local_pos.x / float(Grid.CELL)), feet_row - 1)


## The left cell of a `width`-wide platform in slot `dir`/`ring`.
static func cell_for(local_pos: Vector2, facing: int, dir: String, ring: String, width: int) -> Vector2i:
	var ref := ref_cell(local_pos)
	var offset: Vector2i = SLOTS[dir][ring]
	var anchor := Vector2i(ref.x + facing * offset.x, ref.y + offset.y)
	if facing < 0:
		anchor.x -= width - 1
	return anchor


## The aim a held direction means in the dash-style scheme.
static func dir_from_input(x: int, y: int) -> String:
	if y < 0:
		return "up" if x == 0 else "upfwd"
	if y > 0:
		return "down" if x == 0 else "downfwd"
	return "fwd"
