class_name PlayerBody
extends Node2D

## The player as it is drawn: a white 10 x 10 box with the inventory cut out of
## it (`InventoryMarks`). It sits where the player is shown this frame and is
## squashed by the player's jump and landing. Every edge is snapped to a whole
## world pixel (`Display.snap_rect`), so the body looks as it did when the
## picture was 320 x 180, whatever the resolution and wherever between two
## pixels the interpolated position falls. The marks are cut from the same
## squashed box, so each is a whole pixel too, and may be 0 or 2 wide for a frame.

var _center := Vector2.ZERO
var _squash := Vector2.ONE
## 1 right, -1 left. Set by the player.
var facing := 1:
	set(value):
		if value != facing:
			facing = value
			queue_redraw()
var _state: Node


func _init() -> void:
	# Placed from the player's _process, in world pixels.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	# The autoload is looked up by path so tests that load this script on its own still compile.
	_state = get_node_or_null("/root/GameState")
	if _state != null:
		_state.tokens_changed.connect(queue_redraw)
		_state.abilities_changed.connect(queue_redraw)


## Where the body's centre is shown this frame, and how squashed it is.
func show_at(center: Vector2, squash: Vector2) -> void:
	if center == _center and squash == _squash:
		return
	_center = center
	_squash = squash
	queue_redraw()


func _draw() -> void:
	draw_rect(box(_center, _squash), Color.WHITE)
	if _state == null:
		return
	for mark in marks(_center, _squash, InventoryMarks.pixels(_state.tokens, _state.abilities.imprint_unlocked, facing)):
		draw_rect(mark, Color.BLACK)


## The white box of a body centred on `center`, squashed by `squash`, on whole
## world pixels.
static func box(center: Vector2, squash: Vector2) -> Rect2:
	var half := Vector2.ONE * (InventoryMarks.SIZE * 0.5)
	return Display.snap_rect(Rect2(center - half * squash, half * 2.0 * squash))


## The cut-outs for the body pixels `pixels` (`InventoryMarks.pixels`), each on
## whole world pixels.
static func marks(center: Vector2, squash: Vector2, pixels: Array[Vector2i]) -> Array[Rect2]:
	var half := Vector2.ONE * (InventoryMarks.SIZE * 0.5)
	var out: Array[Rect2] = []
	for p in pixels:
		out.append(Display.snap_rect(Rect2(center + (Vector2(p) - half) * squash, squash)))
	return out
