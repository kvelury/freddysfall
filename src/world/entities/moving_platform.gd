class_name MovingPlatform
extends Node2D

## A moving platform as it is drawn: a white block, like any platform. Its room
## moves it each tick to where its path says. The track is not drawn.

var path: PlatformPath


func _init(platform_path: PlatformPath) -> void:
	path = platform_path
	name = "Platform_%s" % path.id
	position = path.rect_at(0).position


## Puts it where its path has it at `tick`, in its room's space.
func move_to(tick: int) -> void:
	position = path.rect_at(tick).position


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Grid.cell_rect(path.start_cells).size), Color.WHITE, true)
