class_name Shatter
extends Node2D

## A burst of square shards where something broke. They fly out, fall, and
## are gone. Nothing fades: a shard is on or it is off.

const COUNT := 14
const LIFE := 0.5

var _shards: Array[Dictionary] = []
var _age := 0.0


func _init() -> void:
	# Animated in _process, so interpolating it would smear new shards in from the origin.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	# A burst is made where something was, which may be between world pixels.
	global_position = Display.snap(global_position)
	for i in COUNT:
		var angle := TAU * float(i) / float(COUNT) + randf_range(-0.2, 0.2)
		var speed := randf_range(40.0, 110.0)
		_shards.append({
			"position": Vector2.ZERO,
			"velocity": Vector2.from_angle(angle) * speed + Vector2(0.0, -30.0),
			"size": 2.0 if i % 3 == 0 else 1.0,
		})


func _process(delta: float) -> void:
	_age += delta
	for shard in _shards:
		shard["velocity"] += Vector2(0.0, 420.0) * delta
		shard["position"] += shard["velocity"] * delta
	queue_redraw()
	if _age >= LIFE:
		queue_free()


func _draw() -> void:
	for shard in _shards:
		var size: float = shard["size"]
		draw_rect(Rect2((shard["position"] as Vector2).round(), Vector2(size, size)), Color.WHITE)
