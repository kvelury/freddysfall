class_name PlayerBody
extends Node2D

## The player as it is drawn: Freddy the frog (`FreddySprites`), a picture of
## whole world pixels in his colours (`FreddySprites.COLOURS`) that fits the
## player's 10 x 10 box, with the inventory cut out of it in black
## (`InventoryMarks`). It shows the pose and picture the player gives it
## (`PlayerAnimator`, `FreddySprites.animation`): standing, one of the walk
## pictures, in the air, or landing. The node sits on the box's top-left corner, snapped to a whole world
## pixel (`Display.snap`), so the frog looks as it does at 320 x 180 whatever the
## resolution and wherever between two pixels the interpolated position falls.
## Moving it does not redraw it; only a new picture, facing or inventory does.

var _pose := PlayerAnimator.Pose.STAND
var _index := 0
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
	if OS.is_debug_build():
		for problem in FreddySprites.problems():
			push_error("Freddy's pictures: %s" % problem)
	# The autoload is looked up by path so tests that load this script on its own still compile.
	_state = get_node_or_null("/root/GameState")
	if _state != null:
		_state.tokens_changed.connect(queue_redraw)
		_state.abilities_changed.connect(queue_redraw)


## Where the body's centre is shown this frame, and the picture it shows.
func show_at(center: Vector2, pose: PlayerAnimator.Pose, index := 0) -> void:
	position = corner(center)
	if pose == _pose and index == _index:
		return
	_pose = pose
	_index = index
	queue_redraw()


func _draw() -> void:
	var tokens := 0
	var imprint := false
	if _state != null:
		tokens = _state.tokens
		imprint = _state.abilities.imprint_unlocked
	var drawn := FreddySprites.rects(_pose, _index, facing, tokens, imprint)
	for layer in drawn.layers:
		for box in layer.rects:
			draw_rect(box, layer.colour)


## The top-left pixel of the 10 x 10 box of a body centred on `center`, on a
## whole world pixel.
static func corner(center: Vector2) -> Vector2:
	return Display.snap(center - Vector2.ONE * (FreddySprites.SIZE * 0.5))
