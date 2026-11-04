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
		if _visual != null:
			_visual.facing = value

## Which picture the body shows (`PlayerAnimator`), from what the movement did.
var animator := PlayerAnimator.new()
## Set by the tongue while it is out going up, for the picture that shows it.
var lashing_up := false
## Whether the look-up key is held and the body is under the player's control.
## The tests set `scripted_look_up`.
var looking_up := false
var scripted_look_up := false

## Tongue Climb: the last seconds of the hang in which Freddy wiggles. Set when a
## climb begins (`begin_climb`).
var climb_wiggle := 0.0

## Previous physics pose, shared with the frame-rate camera.
var _previous_position := Vector2.ZERO
var _state := MovementSim.State.new()
var _was_on_floor := true
var _visual: PlayerBody


func _ready() -> void:
	_previous_position = global_position
	add_to_group("player")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	if config == null:
		config = load("res://src/player/movement.tres")
	_state.coyote = config.coyote_time
	_visual = $Visual
	_visual.facing = facing


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
	_state.climb = MovementSim.CLIMB_NONE
	_state.climb_abort = false
	_state.climb_locked = false
	_state.spare_jump = false
	_state.released = false
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


## Tongue Climb. The tongue calls this when its tip has stuck to a wall (`dir`
## (+-1, 0)) or the ceiling (`dir` (0, -1)) at `tip`: Freddy is pulled to it and
## hangs for `hold` seconds, wiggling in the last `wiggle` (see
## `MovementSim.start_climb`). False if he is already climbing or must land first.
func begin_climb(tip: Vector2, dir: Vector2, hold: float, wiggle: float, zip_speed: float, relock: bool) -> bool:
	_state.position = global_position
	var rects: Array = solids
	if room != null and is_instance_valid(room) and not room.movers.is_empty():
		# The moving platforms where the body collides with them this tick.
		rects = solids + room.movers.rects(room.tick)
	if not MovementSim.start_climb(_state, rects, tip, dir, hold, zip_speed, relock):
		return false
	climb_wiggle = wiggle
	velocity = Vector2.ZERO
	return true


## Lets go of the wall or ceiling, if he is on one, and falls. Does nothing
## otherwise: it must not touch the velocity of a body that just jumped off.
func end_climb() -> void:
	if not climbing():
		return
	MovementSim.drop_climb(config, _state)
	velocity = Vector2.ZERO


## Drops him at once because the power was taken away (the dev tools): nothing
## is given back, no coyote time and no spare jump. Does nothing if he is not
## climbing.
func cancel_climb() -> void:
	if not climbing():
		return
	MovementSim.release_climb(_state)
	_state.spare_jump = false
	velocity = Vector2.ZERO


## The box the world tests against spikes: where the body is, or, on a tick he
## was pulled to a wall, everything he passed through.
func hazard_rect() -> Rect2:
	return _state.climb_swept if _state.climb_swept.has_area() else body_rect()


## Whether he is being pulled to a wall or hanging on one.
func climbing() -> bool:
	return _state.climb != MovementSim.CLIMB_NONE


## Whether he has arrived and is hanging (as against being pulled there).
func hanging() -> bool:
	return _state.climb == MovementSim.CLIMB_HOLD


## Whether he is hanging from a ceiling, as against a wall.
func climbing_ceiling() -> bool:
	return climbing() and _state.climb_dir.y < 0.0


## Whether the hang is in its last seconds, when he wiggles.
func wiggling() -> bool:
	return MovementSim.wiggling(_state, climb_wiggle)


## Whether he must land before he can stick again (Land before re-stick).
func climb_locked() -> bool:
	return _state.climb_locked


## The body's box in world pixels.
func body_rect() -> Rect2:
	return Rect2(global_position - MovementSim.HALF, MovementSim.HALF * 2.0)


func _physics_process(delta: float) -> void:
	# Held players can still move on a save-machine tween later in this tick.
	_previous_position = global_position
	if not input_enabled:
		looking_up = false
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
	# Stuck to a wall he keeps facing it: left and right only steer the jump.
	if input_x != 0.0 and signf(input_x) != float(facing) and not climbing():
		facing = int(signf(input_x))
	scripted_jump_pressed = false
	looking_up = not blocked and not climbing() and (scripted_look_up if scripted else Input.is_action_pressed("look_up"))
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
	if _state.air_jumped:
		_spawn_dust(true)
	elif _state.jumped and _state.released:
		_spawn_dust()
	if _state.grounded and not _was_on_floor:
		animator.land()
		_spawn_dust()
	_was_on_floor = _state.grounded


func _process(delta: float) -> void:
	if _visual == null:
		return
	var hang := PlayerAnimator.Hang.NONE
	if climbing():
		hang = PlayerAnimator.Hang.CEILING if climbing_ceiling() else PlayerAnimator.Hang.WALL
	animator.advance(delta, _state.grounded, velocity.x, lashing_up, looking_up, hang)
	var fraction := Engine.get_physics_interpolation_fraction() if is_physics_interpolated_and_enabled() else 1.0
	var index := FreddySprites.animation(animator.pose).index(animator.time_in_pose, animator.distance_in_pose)
	_visual.show_at(render_position(fraction), animator.pose, index, wiggle_offset())
	_visual.shake = wiggle_offset()


## How far the wiggle shifts the picture this frame, in whole world pixels: 1 px
## to one side and then the other, about every twentieth of a second, while the
## hang is running out. Zero otherwise. It moves the picture only, not the body.
func wiggle_offset() -> Vector2:
	if not wiggling():
		return Vector2.ZERO
	return Vector2(1.0 if int(animator.time_in_pose * 20.0) % 2 == 0 else -1.0, 0.0)


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

	## Where the speck is, between world pixels. The node sits on the world
	## pixel that speck's 1 x 1 box lights.
	var _exact := Vector2.ZERO

	func _ready() -> void:
		_exact = position
		_place()

	func _process(delta: float) -> void:
		life -= delta
		_exact += velocity * delta
		velocity.y += 420.0 * delta
		_place()
		queue_redraw()
		if life <= 0.0:
			queue_free()

	func _place() -> void:
		position = Display.snap(_exact - Vector2(0.5, 0.5))

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), Color.WHITE)
