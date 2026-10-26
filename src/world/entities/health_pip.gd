class_name HealthPip
extends Node2D

## A health pip lying in a room. Touch it and GameState.health goes up by one:
## a death spends a pip and puts the player back on the last safe floor instead
## of at their save room. Taking it is kept in the flags, so the room builds
## without it from then on, even once the pip is spent.

var def: EntityDef
var _age := 0.0


func _init(entity: EntityDef = null) -> void:
	def = entity
	# The bob is drawn in _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func flag_for(entity: EntityDef) -> String:
	return "health:" + entity.id


## The area that collects it, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position - Vector2(Pickup.HALF, Pickup.HALF), Vector2(Pickup.HALF, Pickup.HALF) * 2.0)


func collect() -> void:
	var burst := Shatter.new()
	burst.position = position
	get_parent().add_child(burst)
	queue_free()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


## A plus sign that bobs, so it reads apart from the diamond pickup and token.
func _draw() -> void:
	var c := Vector2(0.0, roundf(sin(_age * 3.0) * 1.5))
	draw_rect(Rect2(c + Vector2(-1, -4), Vector2(2, 8)), Color.WHITE)
	draw_rect(Rect2(c + Vector2(-4, -1), Vector2(8, 2)), Color.WHITE)
