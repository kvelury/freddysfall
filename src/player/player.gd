class_name Player
extends Node2D

@export var config: MovementConfig

var velocity := Vector2.ZERO
var input_enabled := true
## Pixel rects the body collides with, in world space. `place` sets them when
## the player is put into a room.
var solids: Array[Rect2] = []
## The room the player is in, for its moving platforms and its clock. The
## world sets it whenever it places the player. Without one, nothing moves.
var room: Room = null
## Used by the headless tests. Gameplay leaves this off.
var scripted := false
var scripted_x := 0.0
var scripted_jump_pressed := false
var scripted_jump_held := false
## Air jumps the body may make before it lands. The world sets it from
## GameState.abilities. A change clamps what is left of the current jump.
var air_jumps := 0:
	set(value):
		air_jumps = maxi(0, value)
		_state.air_jumps = air_jumps
		_state.air_left = mini(_state.air_left, air_jumps)
## Which way the player last chose to go: 1 right, -1 left. It turns with left
## or right input and is not part of the movement. A placed Imprint uses it to
## break a tie (the block behind the player goes first), and the body shows it.
## The world turns it right again on spawn, respawn and warp.
var facing := 1:
	set(value):
		facing = value
		if _marks != null:
			_marks.facing = value

## Previous physics pose, shared with the frame-rate camera.
var _previous_position := Vector2.ZERO
var _state := MovementSim.State.new()
var _was_on_floor := true
var _squash := 0.0
var _visual: Polygon2D
var _marks: InventoryMarks


func _ready() -> void:
	_previous_position = global_position
	add_to_group("player")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	if config == null:
		config = load("res://src/player/movement.tres")
	_state.coyote = config.coyote_time
	_visual = $Visual
	_marks = InventoryMarks.new()
	_marks.facing = facing
	_visual.add_child(_marks)


## Puts the body at rest in a room: at `world_position`, among `rects`.
func place(world_position: Vector2, rects: Array[Rect2]) -> void:
	global_position = world_position
	_previous_position = world_position
	velocity = Vector2.ZERO
	solids = rects
	_state.grounded = MovementSim.standing(world_position, rects)
	_state.coyote = config.coyote_time if _state.grounded else 0.0
	_state.buffer = 0.0
	_state.air_left = air_jumps
	_state.launched = false
	_state.cut = false
	_state.riding = -1
	_state.crushed = false
	_was_on_floor = _state.grounded
	reset_physics_interpolation()


## The displayed position between physics ticks. Only the camera reads it;
## collisions, interaction checks and the solver keep using the physics pose.
func render_position(fraction: float) -> Vector2:
	if not is_physics_interpolated_and_enabled():
		return global_position
	return _previous_position.lerp(global_position, fraction)


func is_on_floor() -> bool:
	return _state.grounded


## The moving platform the player is standing on, or -1.
func riding() -> int:
	return _state.riding


## Whether a moving platform pushed the player into a wall this tick.
func crushed() -> bool:
	return _state.crushed


## The body's box in world pixels.
func body_rect() -> Rect2:
	return Rect2(global_position - MovementSim.HALF, MovementSim.HALF * 2.0)


func _physics_process(delta: float) -> void:
	# Held players can still move on a save-machine tween later in this tick.
	_previous_position = global_position
	if not input_enabled:
		velocity = Vector2.ZERO
		# Held still, the player is not carried, so they are not riding when let go.
		_state.riding = -1
		return
	var blocked: bool = not scripted and get_parent().has_method("gameplay_input_blocked") and get_parent().gameplay_input_blocked()
	var input_x := scripted_x if scripted else Input.get_axis("move_left", "move_right")
	var jump_pressed := scripted_jump_pressed if scripted else Input.is_action_just_pressed("jump")
	var jump_held := scripted_jump_held if scripted else Input.is_action_pressed("jump")
	if blocked:
		input_x = 0.0
		jump_pressed = false
		jump_held = false
	if input_x != 0.0 and signf(input_x) != float(facing):
		facing = int(signf(input_x))
	scripted_jump_pressed = false
	_state.position = global_position
	_state.velocity = velocity
	var movers: Movers = null
	var tick := 0
	if room != null and is_instance_valid(room) and not room.movers.is_empty():
		movers = room.movers
		# The room has already moved its platforms to this tick.
		tick = room.tick - 1
	MovementSim.step(config, _state, solids, input_x, jump_pressed, jump_held, delta, movers, tick)
	global_position = _state.position
	velocity = _state.velocity
	if _state.jumped:
		_squash = 1.0
	if _state.air_jumped:
		_spawn_dust(true)
	if _state.grounded and not _was_on_floor:
		_squash = -1.0
		_spawn_dust()
	_was_on_floor = _state.grounded


func _process(delta: float) -> void:
	if _visual == null:
		return
	if _squash > 0.0:
		_visual.scale = Vector2(0.9, 1.1).lerp(Vector2.ONE, 1.0 - _squash)
		_squash = maxf(0.0, _squash - delta * 8.0)
	elif _squash < 0.0:
		_visual.scale = Vector2(1.1, 0.9).lerp(Vector2.ONE, 1.0 + _squash)
		_squash = minf(0.0, _squash + delta * 8.0)
	else:
		_visual.scale = Vector2.ONE


func _spawn_dust(downward := false) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for _i in 3:
		var dust := Dust.new()
		dust.position = parent.to_local(global_position + Vector2(randf_range(-4.0, 4.0), 5.0))
		dust.velocity = Vector2(randf_range(-28.0, 28.0), randf_range(-40.0, -12.0))
		if downward:
			dust.velocity.y = randf_range(10.0, 40.0)
		parent.add_child(dust)


class Dust extends Node2D:
	var velocity := Vector2.ZERO
	var life := 0.22

	func _init() -> void:
		# Animated in _process; interpolating it smears new pixels from the parent origin.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	func _process(delta: float) -> void:
		life -= delta
		position += velocity * delta
		velocity.y += 420.0 * delta
		queue_redraw()
		if life <= 0.0:
			queue_free()

	func _draw() -> void:
		draw_rect(Rect2(-0.5, -0.5, 1.0, 1.0), Color.WHITE)
