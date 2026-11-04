class_name LookAhead
extends RefCounted

## How far the view is shifted by looking up or down: a quarter of a screen, once
## the key has been held `HOLD_TIME` seconds, and it glides there and back. Pure:
## no node, no input and no autoload, so a test drives it with `step`, as
## `PlayerAnimator` and `MovementSim` are driven. `Player` steps it once a physics
## tick, and `World` reads `offset` for the camera each rendered frame.

## How long the key is held before the view starts to move, in seconds.
const HOLD_TIME := 1.15
## How far the view shifts, in world px: a quarter of the screen's height.
const OFFSET := Grid.SCREEN_SIZE.y / 4.0
## How long the glide takes, in seconds, each way.
const GLIDE_TIME := 0.25

## The direction held: -1 up, 1 down, 0 neither (or one that does not count now).
var held_dir := 0
## Seconds the current direction has been held.
var held_time := 0.0
## How far through the glide, from -1 (fully up) to 1 (fully down).
var progress := 0.0

var _previous := 0.0


## Moves on by `delta` seconds with `dir` held (-1 up, 1 down, 0 none). A change
## of direction, or letting go, restarts the hold.
func step(delta: float, dir: int) -> void:
	_previous = progress
	if dir != held_dir:
		held_dir = dir
		held_time = 0.0
	if dir != 0:
		held_time += delta
	var target := float(dir) if dir != 0 and held_time >= HOLD_TIME else 0.0
	progress = move_toward(progress, target, delta / GLIDE_TIME)


## The shift of the view in world px (negative is up), between the last two steps
## at `fraction` of the way. Whole numbers are the camera's business, not this.
func offset(fraction := 1.0) -> float:
	return OFFSET * _eased(lerpf(_previous, progress, fraction))


## Back to rest with no glide, for a new room, a respawn or a retry.
func reset() -> void:
	held_dir = 0
	held_time = 0.0
	progress = 0.0
	_previous = 0.0


static func _eased(p: float) -> float:
	return signf(p) * smoothstep(0.0, 1.0, absf(p))
