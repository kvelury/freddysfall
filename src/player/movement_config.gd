class_name MovementConfig
extends Resource

@export var run_speed := 90.0
@export var ground_accel := 900.0
@export var ground_friction := 1200.0
@export var air_accel := 600.0
@export var air_friction := 300.0
@export var jump_speed := 267.0
@export var gravity := 740.0
@export var jump_cut := 0.4
@export var apex_threshold := 40.0
@export var apex_gravity_scale := 0.5
@export var fall_gravity_scale := 1.8
@export var max_fall_speed := 300.0
@export var jump_buffer := 0.12
@export var coyote_time := 0.10
@export var corner_correction := 3.0
## Whether a body that jumps or walks off a moving platform keeps the
## platform's velocity as well as its own. Off: leaving a platform feels like
## leaving any floor. It was tried on in playtesting.
@export var inherit_platform_velocity := false
