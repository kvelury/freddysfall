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
## Tongue Climb's wiggle: how far the picture is shifted from the body this
## frame, in world pixels. The tongue is drawn to the same tip whatever it is.
var shake := Vector2.ZERO
var _state: Node
var _fine: FinePupils


## The pupils that are half a world pixel tall (looking down). Finer than the
## world-pixel grid by decision, so they are in `Display.FINE_GROUP`, which the
## pixel check leaves out.
class FinePupils extends Node2D:
	var body: PlayerBody

	func _init() -> void:
		add_to_group(Display.FINE_GROUP)

	func _draw() -> void:
		for box in FreddySprites.fine_rects(body._pose, body._index, body.facing):
			draw_rect(box, Color.BLACK)


func _init() -> void:
	# Placed from the player's _process, in world pixels.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fine = FinePupils.new()
	_fine.body = self
	add_child(_fine)


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
func show_at(center: Vector2, pose: PlayerAnimator.Pose, index := 0, offset := Vector2.ZERO) -> void:
	position = corner(center) + offset
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
	_fine.queue_redraw()


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


## The pixels the tongue fills when it reaches `extension` pixels past the front
## of the body, in world pixels: one row, from inside the mouth notch out. The
## picture on show says which row the mouth is on.
func tongue_rect(extension: float) -> Rect2:
	var frames_of := FreddySprites.animation(_pose).frames
	var mouth := frames_of[posmod(_index, frames_of.size())].mouth
	var reach := roundf(extension)
	var size := float(FreddySprites.SIZE)
	if facing < 0:
		return Rect2(position + Vector2(-reach, float(mouth)), Vector2(reach + 2.0, 1.0))
	return Rect2(position + Vector2(size - 2.0, float(mouth)), Vector2(reach + 2.0, 1.0))


## The pixels the tongue fills going up, in world pixels: one column, from inside
## the mouth on top of the head to `extension` pixels above the top of the body.
func tongue_rect_up(extension: float) -> Rect2:
	var frames_of := FreddySprites.animation(_pose).frames
	var frame := frames_of[posmod(_index, frames_of.size())]
	var mouth := frame.mouth_up if frame.mouth_up.x >= 0 else FreddySprites.LASH_UP_MOUTH
	var column := mouth.x if facing > 0 else FreddySprites.SIZE - 1 - mouth.x
	var reach := roundf(extension)
	return Rect2(position + Vector2(float(column), -reach), Vector2(1.0, reach + float(mouth.y) + 1.0))


## The pad at the tongue's tip while it is stuck (`Abilities.tongue_pad`): two
## pixels wide and three tall, centred on the mouth row, at the tip's end.
func pad_rect(extension: float) -> Rect2:
	var line := tongue_rect(extension)
	if facing < 0:
		return Rect2(line.position + Vector2(0.0, -1.0), Vector2(2.0, 3.0))
	return Rect2(Vector2(line.end.x - 2.0, line.position.y - 1.0), Vector2(2.0, 3.0))


## The pad going up: three pixels wide and two tall, at the top of the tongue.
func pad_rect_up(extension: float) -> Rect2:
	var line := tongue_rect_up(extension)
	return Rect2(line.position + Vector2(-1.0, 0.0), Vector2(3.0, 2.0))


## The top-left pixel of the 10 x 10 box of a body centred on `center`, on a
## whole world pixel.
static func corner(center: Vector2) -> Vector2:
	return Display.snap(center - Vector2.ONE * (FreddySprites.SIZE * 0.5))
