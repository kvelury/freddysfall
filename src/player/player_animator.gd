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

## What the body is doing. `FreddySprites` maps each to the pictures that play for it.
enum Pose { STAND, WALK, JUMP, LAND }

var pose := Pose.STAND
## Seconds and ground px since `pose` began. Both start from 0 on every change of pose.
var time_in_pose := 0.0
var distance_in_pose := 0.0

var _landing_left := 0.0


## The body has just touched down.
func land() -> void:
	_landing_left = LAND_TIME


## Moves on by `delta` seconds of a body that is `grounded` and moving at
## `speed_x` px/s, and sets `pose`, `time_in_pose` and `distance_in_pose`. In
## the air is the jump; just landed is the landing; running walks. How many
## pictures a pose has and how fast they play is not decided here.
func advance(delta: float, grounded: bool, speed_x: float) -> void:
	var landing := _landing_left > 0.0
	_landing_left = maxf(0.0, _landing_left - delta)
	var next := Pose.STAND
	if not grounded:
		next = Pose.JUMP
	elif landing:
		next = Pose.LAND
	elif absf(speed_x) > WALK_SPEED:
		next = Pose.WALK
	if next != pose:
		pose = next
		time_in_pose = 0.0
		distance_in_pose = 0.0
	time_in_pose += delta
	if grounded:
		distance_in_pose += absf(speed_x) * delta
