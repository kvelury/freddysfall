class_name Pickup
extends Node2D

## An upgrade lying in a room. Touch it and it is yours for good: the flag is
## kept in GameState, so the room builds without it from then on.

const HALF := 4.0

var def: EntityDef
var _age := 0.0


func _init(entity: EntityDef = null) -> void:
	def = entity
	# The bob is drawn in _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func flag_for(entity: EntityDef) -> String:
	return "pickup:" + entity.id


## The area that collects it, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0)


func collect() -> void:
	var burst := Shatter.new()
	burst.position = position
	get_parent().add_child(burst)
	queue_free()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


## A diamond that bobs a pixel or two, with a hollow middle so it reads as a
## thing to take and not as a block.
func _draw() -> void:
	var lift := roundf(sin(_age * 3.0) * 1.5)
	var c := Vector2(0.0, lift)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), Color.WHITE)
	draw_rect(Rect2(c + Vector2(-1, -1), Vector2(2, 2)), Color.BLACK)
