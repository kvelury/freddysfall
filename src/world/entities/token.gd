class_name Token
extends Node2D

## A token lying in a room. Touch it and the player carries it, up to
## GameState.TOKEN_CAP. Tokens are spent at a 3TM. Taking one is kept in the
## flags, so the room builds without it from then on, even once it is spent.

var def: EntityDef
## Whether the player has already been told they are full while standing in it.
var noted := false
var _age := 0.0


func _init(entity: EntityDef = null) -> void:
	def = entity
	# The bob is drawn in _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func flag_for(entity: EntityDef) -> String:
	return "token:" + entity.id


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


## A solid diamond that bobs, so it reads apart from the hollow upgrade pickup.
func _draw() -> void:
	draw_token(self, Vector2(0.0, roundf(sin(_age * 3.0) * 1.5)))


## The token shape, centred on `at`, drawn onto `canvas`. The 3TM and the
## flying token use it too, so every token looks the same.
static func draw_token(canvas: CanvasItem, at: Vector2, color := Color.WHITE) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0), at + Vector2(0, 4), at + Vector2(-4, 0)]), color)
