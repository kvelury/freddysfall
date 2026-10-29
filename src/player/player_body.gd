class_name PlayerBody
extends Node2D

## The player as it is drawn: Freddy the frog (`FreddySprites`), a picture of
## whole world pixels in his colours (`FreddySprites.COLOURS`) that fits the
## player's 10 x 10 box, with the inventory cut out of it in black
## (`InventoryMarks`): a mark for each token only when the dev tools switch it
## on (`DevSession.token_marks_active`), and never the Imprint line. It shows
## the pose and picture the player gives it (`PlayerAnimator`,
## `FreddySprites.animation`): standing, one of the walk pictures, in the air, or
## landing. The node sits on the box's top-left corner, snapped to a whole world
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
	var dev := get_node_or_null("/root/DevSession")
	if dev != null:
		dev.token_marks_changed.connect(queue_redraw)


## Where the body's centre is shown this frame, and the picture it shows.
func show_at(center: Vector2, pose: PlayerAnimator.Pose, index := 0) -> void:
	position = corner(center)
	if pose == _pose and index == _index:
		return
	_pose = pose
	_index = index
	queue_redraw()


func _draw() -> void:
	var drawn := FreddySprites.rects(_pose, _index, facing, shown_tokens(), shown_imprint())
	for layer in drawn.layers:
		for box in layer.rects:
			draw_rect(box, layer.colour)


## How many tokens are drawn as marks: none, unless a dev test has turned them on.
func shown_tokens() -> int:
	var dev := get_node_or_null("/root/DevSession")
	if _state == null or dev == null or not dev.token_marks_active():
		return 0
	return _state.tokens


## Whether the Imprint line is drawn: never. It sat on the row above the gap
## between his legs and read as a bite out of his belly. The pictures still carry
## its place (`FreddySprites.Frame.line`), so showing it again is a change here.
func shown_imprint() -> bool:
	return false


## The top-left pixel of the 10 x 10 box of a body centred on `center`, on a
## whole world pixel.
static func corner(center: Vector2) -> Vector2:
	return Display.snap(center - Vector2.ONE * (FreddySprites.SIZE * 0.5))
