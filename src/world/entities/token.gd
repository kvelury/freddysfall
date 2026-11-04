class_name Token
extends Node2D

## A token lying in a room. Touch it and the player carries it, up to
## GameState.TOKEN_CAP. Tokens are spent at a 3TM. Taking one is kept in the
## flags, so the room builds without it from then on, even once it is spent.

## A token and a health pip float half a cell above the cell they are placed in:
## the picture and the area that collects it both move up, and the bob is
## unchanged. Half a cell is still inside the cell, so a player standing on the
## floor beside one walks into it.
const RAISE := float(Grid.CELL) * 0.5

var def: EntityDef
var _age := 0.0
var _lift := 0.0


func _init(entity: EntityDef = null) -> void:
	def = entity
	# The bob is drawn in _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func flag_for(entity: EntityDef) -> String:
	return "token:" + entity.id


## The area that collects it, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position - Vector2(Pickup.HALF, Pickup.HALF + RAISE), Vector2(Pickup.HALF, Pickup.HALF) * 2.0)


func collect() -> void:
	var burst := Shatter.new()
	burst.position = position
	get_parent().add_child(burst)
	queue_free()


func _process(delta: float) -> void:
	_age += delta
	var lift := roundf(sin(_age * 3.0) * 1.5)
	if lift != _lift:
		_lift = lift
		queue_redraw()


## A solid gold diamond that bobs, so it reads apart from the hollow upgrade
## pickup. It is the flying token's 11 x 12 picture, as wide as a room's health
## pip.
func _draw() -> void:
	PixelArt.draw(self, "flying_token", Vector2(0.0, _lift - RAISE), Palette.GOLD)


## The small token shape, centred on `at`, drawn onto `canvas`. The 3TM's
## openings use it, so a token fits in one.
static func draw_token(canvas: CanvasItem, at: Vector2, color := Palette.GOLD) -> void:
	PixelArt.draw(canvas, "token", at, color)
