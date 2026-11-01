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


## The HUD's red heart, bobbing, centred on the bob point, so it reads as the
## heart it becomes.
func _draw() -> void:
	var c := Vector2(0.0, roundf(sin(_age * 3.0) * 1.5))
	draw_heart(self, c + Vector2(-3, -3))


## The heart shape, with its top-left at `at`, drawn onto `canvas`. The HUD's
## flying pip uses it too, so every pip looks the same.
static func draw_heart(canvas: CanvasItem, at: Vector2, color := Palette.RED) -> void:
	PixelArt.draw(canvas, "hud_heart", at, color)
