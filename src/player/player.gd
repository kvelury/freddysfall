class_name Player
extends CharacterBody2D

@export var config: MovementConfig

var input_enabled := true
## Used by the headless physics test. Gameplay leaves this off.
var scripted := false
var scripted_x := 0.0
var scripted_jump_pressed := false
var scripted_jump_held := false

var _coyote := 0.0
var _buffer := 0.0
var _launched := false
var _cut := false
var _was_on_floor := true
var _squash := 0.0
var _visual: Polygon2D
var _out := {
	"velocity": Vector2.ZERO,
	"coyote": 0.0,
	"buffer": 0.0,
	"launched": false,
	"cut": false,
	"jumped": false,
}


func _ready() -> void:
	add_to_group("player")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	floor_snap_length = 2.0
	up_direction = Vector2.UP
	if config == null:
		config = load("res://src/player/movement.tres")
	_coyote = config.coyote_time
	_visual = $Visual


func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		return
	var input_x := scripted_x if scripted else Input.get_axis("move_left", "move_right")
	var jump_pressed := scripted_jump_pressed if scripted else Input.is_action_just_pressed("jump")
	var jump_held := scripted_jump_held if scripted else Input.is_action_pressed("jump")
	scripted_jump_pressed = false
	var grounded := _on_ground()
	MovementSim.integrate(
		config, velocity, grounded, _coyote, _buffer, _launched, _cut,
		input_x, jump_pressed, jump_held, delta, _out
	)
	velocity = _out["velocity"]
	_coyote = _out["coyote"]
	_buffer = _out["buffer"]
	_launched = _out["launched"]
	_cut = _out["cut"]
	if _out["jumped"]:
		_squash = 1.0
	_corner_correct(delta)
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_squash = -1.0
		_spawn_dust()
	_was_on_floor = on_floor
	if on_floor:
		_launched = false
		_cut = false


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


func _on_ground() -> bool:
	if is_on_floor():
		return true
	if velocity.y < 0.0:
		return false
	return test_move(global_transform, Vector2(0.0, 2.0))


func _corner_correct(delta: float) -> void:
	var max_px := int(round(config.corner_correction))
	if max_px <= 0:
		return
	if not is_on_floor() and absf(velocity.x) > 1.0 and velocity.y >= 0.0:
		var horiz := Vector2(velocity.x * delta, 0.0)
		if test_move(global_transform, horiz):
			for n in max_px:
				var lift := float(n + 1)
				if not test_move(global_transform.translated(Vector2(0.0, -lift)), horiz):
					position.y -= lift
					break
	if velocity.y < 0.0:
		var vert := Vector2(0.0, velocity.y * delta)
		if test_move(global_transform, vert):
			var prefer := signf(velocity.x) if absf(velocity.x) > 1.0 else 1.0
			var pushed := false
			for dir in [prefer, -prefer]:
				if pushed:
					break
				var direction := float(dir)
				for n in max_px:
					var push := float(n + 1) * direction
					if not test_move(global_transform.translated(Vector2(push, 0.0)), vert):
						position.x += push
						pushed = true
						break


func _spawn_dust() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for _i in 3:
		var dust := Dust.new()
		dust.position = parent.to_local(global_position + Vector2(randf_range(-4.0, 4.0), 5.0))
		dust.velocity = Vector2(randf_range(-28.0, 28.0), randf_range(-40.0, -12.0))
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
