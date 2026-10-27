class_name MovingPlatform
extends Node2D

## A moving platform as it is drawn: a white block, like any platform. Its room
## moves it each tick to where its path says. The track is not drawn.
##
## It is drawn where it is between two ticks, on a whole world pixel, which is
## what the engine's interpolation gave at 320 x 180.

var path: PlatformPath
var _previous := Vector2.ZERO
var _current := Vector2.ZERO


func _init(platform_path: PlatformPath) -> void:
	path = platform_path
	name = "Platform_%s" % path.id
	_current = path.rect_at(0).position
	_previous = _current
	position = Display.snap(_current)
	# Placed from _process, so interpolating it would only lag it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Puts it where its path has it at `tick`, in its room's space.
func move_to(tick: int) -> void:
	_previous = _current
	_current = path.rect_at(tick).position


func _process(_delta: float) -> void:
	position = shown_at(Engine.get_physics_interpolation_fraction())


## Where it is drawn `fraction` of the way from the last tick to this one: a
## whole world pixel.
func shown_at(fraction: float) -> Vector2:
	return Display.snap(_previous.lerp(_current, fraction))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Grid.cell_rect(path.start_cells).size), Color.WHITE, true)
