class_name PlayerAnimator
extends RefCounted

## Which of Freddy's pictures (`FreddySprites`) the body shows, worked out from
## what the movement did. It has no node and reads no input, so a test can
## drive it directly, as `MovementSim` is driven. `Player` calls `land` when the
## body touches down and `advance` once a rendered frame.

## How long the landing picture shows, in seconds.
const LAND_TIME := 0.125
## Slower than this on the ground, in px/s, and the body stands instead of walking.
const WALK_SPEED := 1.0
## How far the body runs, in px, for each walk picture.
const STRIDE_PER_PICTURE := 6.0

var pose := FreddySprites.Pose.STAND
## The walk picture, while `pose` is WALK. 0 otherwise.
var step := 0

var _landing_left := 0.0
## How far the body has run on the ground since it last stood, in px.
var _stride := 0.0


## The body has just touched down.
func land() -> void:
	_landing_left = LAND_TIME


## Moves on by `delta` seconds of a body that is `grounded` and moving at
## `speed_x` px/s, and sets `pose` and `step`. In the air is the jump picture;
## just landed is the landing picture; running walks, a picture every
## `STRIDE_PER_PICTURE` px, from the first again each time it stops.
func advance(delta: float, grounded: bool, speed_x: float) -> void:
	var landing := _landing_left > 0.0
	_landing_left = maxf(0.0, _landing_left - delta)
	step = 0
	if not grounded:
		pose = FreddySprites.Pose.JUMP
		_stride = 0.0
	elif landing:
		pose = FreddySprites.Pose.LAND
		_stride = 0.0
	elif absf(speed_x) > WALK_SPEED:
		pose = FreddySprites.Pose.WALK
		_stride += absf(speed_x) * delta
		step = int(_stride / STRIDE_PER_PICTURE) % FreddySprites.walk_length()
	else:
		pose = FreddySprites.Pose.STAND
		_stride = 0.0
