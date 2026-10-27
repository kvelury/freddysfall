class_name FlyingToken
extends Node2D

## A token, or a spark, that flies from one place to another along an arc and
## says so when it lands. The 3TM uses it to make a deposit impossible to miss.
## It leaves a trail of dots behind it. Nothing fades: a dot is on or it is off.

signal arrived

const TRAIL := 6

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _duration := 0.4
var _time := 0.0
var _spark := false
var _trail: Array[Vector2] = []


## Adds a flier under `parent` and starts it. `spark` makes a small square
## instead of a token.
static func launch(parent: Node, from: Vector2, to: Vector2, duration: float, spark := false) -> FlyingToken:
	var flier := FlyingToken.new()
	flier._from = from
	flier._to = to
	flier._duration = maxf(duration, 0.01)
	flier._spark = spark
	flier.z_index = 10
	parent.add_child(flier)
	flier.global_position = Display.snap(from)
	return flier


func _init() -> void:
	# Moved in _process, so interpolating it would only lag it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_time += delta
	var t := clampf(_time / _duration, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	_trail.append(global_position)
	if _trail.size() > TRAIL:
		_trail.pop_front()
	global_position = (_from.lerp(_to, eased) + Vector2(0.0, -sin(PI * t) * 16.0)).round()
	queue_redraw()
	if t >= 1.0:
		arrived.emit()
		queue_free()


func _draw() -> void:
	for i in _trail.size():
		var dot := to_local(_trail[i])
		if i % 2 == 0:
			draw_rect(Display.snap_rect(Rect2(dot.round() - Vector2.ONE * 0.5, Vector2.ONE)), Color.WHITE)
	if _spark:
		draw_rect(Display.snap_rect(Rect2(-1.5, -1.5, 3, 3)), Color.WHITE)
	else:
		# A little bigger than the token in the world, so it reads as leaving the body.
		PixelArt.draw(self, "flying_token", Vector2.ZERO)
