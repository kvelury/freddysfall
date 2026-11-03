class_name JumpPlan
extends RefCounted

## One input plan for MovementSim.run: where a body starts, what it presses and
## for how long, and what it is tested against. Every field has the value a
## plain standing jump wants, so a caller sets only what differs.

## The solids, as pixel rects.
var rects: Array = []
var start_position := Vector2.ZERO
var start_velocity := Vector2.ZERO
## Horizontal input, -1 to 1, held from the start.
var input_x := 0.0
## How many ticks the jump button is held.
var hold_frames := 0
## Whether the body starts on the ground (with coyote time to jump).
var grounded_start := true
## False walks (or drops) without pressing jump.
var jump := true
## Rects that end the path when touched; the result's "trigger" is the index.
var triggers: Array = []
## The path ends when the body leaves this. Empty means no limit.
var bounds := Rect2()
## Rects that kill: the path ends with "hazard".
var hazards: Array = []
## Rects the path takes when it touches them (the result's "collected").
var collect: Array = []
## Input from `switch_frame` on, if not NAN.
var later_input := NAN
var switch_frame := 0
## The most ticks the path may run.
var limit := 180
## Keep every position in the result's "path".
var record := false
## The room's moving platforms, at `start_tick` on the first tick, and the one
## the body starts standing on, or -1.
var movers: Movers = null
var start_tick := 0
var start_riding := -1
## Air jumps the body has, and a second press at `air_frame` (ticks after the
## start) held for `air_hold` ticks, or -1 for none.
var air_jumps := 0
var air_frame := -1
var air_hold := 0


func _init(solids: Array = [], at := Vector2.ZERO, moving := Vector2.ZERO, input := 0.0, hold := 0) -> void:
	rects = solids
	start_position = at
	start_velocity = moving
	input_x = input
	hold_frames = hold
