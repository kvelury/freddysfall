class_name InventoryMarks
extends Node2D

## The player's inventory, drawn on the body: a small 2 x 1 line cut out for each
## token carried, and a line near the bottom once Imprint is found. It is a
## child of the body sprite, so it squashes with it.
##
## The body is 10 x 10 pixels. Cut-outs are black, in pixel columns and rows
## counted from the top left. Tokens stack bottom to top on the side opposite
## facing, one pixel inside the body edge with one clear row between lines.
## The Imprint line sits below the stack with one clear row between them.
## A 2 x 2 block in a top corner, one row down, shows which way the player
## faces: on the right when facing right, on the left when facing left.

const SIZE := 10
## The left pixel of each token's 2 x 1 line when facing right, bottom first.
const SLOTS: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 4), Vector2i(1, 2)]
const WIDTH := 2
const LINE_ROW := 8
const LINE_FROM := 1
const LINE_TO := 8
const FACE_RIGHT: Array[Vector2i] = [Vector2i(8, 1), Vector2i(9, 1), Vector2i(8, 2), Vector2i(9, 2)]
const FACE_LEFT: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)]

## 1 right, -1 left. Set by the player.
var facing := 1:
	set(value):
		if value != facing:
			facing = value
			queue_redraw()

var _state: Node


func _ready() -> void:
	# Drawn when the inventory changes, never animated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The autoload is looked up by path so tests that load this script on its own still compile.
	_state = get_node_or_null("/root/GameState")
	if _state != null:
		_state.tokens_changed.connect(queue_redraw)
		_state.abilities_changed.connect(queue_redraw)
	queue_redraw()


## The body pixels cut out for `tokens` carried, Imprint found or not, and the
## block for `facing` (0 omits the block and uses the right-facing stack).
static func pixels(tokens: int, imprint: bool, face := 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in mini(tokens, SLOTS.size()):
		for dx in WIDTH:
			var p := SLOTS[i] + Vector2i(dx, 0)
			out.append(Vector2i(SIZE - 1 - p.x, p.y) if face < 0 else p)
	if imprint:
		for x in range(LINE_FROM, LINE_TO + 1):
			out.append(Vector2i(x, LINE_ROW))
	if face != 0:
		out.append_array(FACE_RIGHT if face > 0 else FACE_LEFT)
	return out


func _draw() -> void:
	if _state == null:
		return
	for p in pixels(_state.tokens, _state.abilities.imprint_unlocked, facing):
		draw_rect(Rect2(Vector2(p) - Vector2(SIZE, SIZE) * 0.5, Vector2.ONE), Color.BLACK)
