class_name SpinnerView
extends Node2D

## A spinner's blocks as they are drawn: a white block for each safe cell and a
## row of spike teeth for each spiked one, pointing away from the middle of the
## bar. The room moves it each tick. Each block is drawn on a whole world pixel,
## like a moving platform.

## How far each pixel of a block's edge a tooth stands out, across the cell.
const TEETH: Array[int] = [1, 3, 5, 3, 1, 1, 3, 5, 3, 1]

var path: SpinnerPath
var _tick := 0
var _current: Array[Vector2] = []
var _previous: Array[Vector2] = []


func _init(spinner_path: SpinnerPath, tick := 0) -> void:
	path = spinner_path
	name = "Spinner_%s" % path.id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for body in path.body_count():
		_current.append(path.rect_at(tick, body).position)
		_previous.append(_current[body])


func move_to(tick: int) -> void:
	_tick = tick
	for body in path.body_count():
		_previous[body] = _current[body]
		_current[body] = path.rect_at(tick, body).position
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func shown_at(body: int, fraction: float) -> Vector2:
	return Display.snap(_previous[body].lerp(_current[body], fraction))


func _draw() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for body in path.body_count():
		var at := shown_at(body, fraction)
		if path.is_hazard(body):
			_teeth(at, path.offsets[body])
		else:
			draw_rect(Rect2(at, Vector2(Grid.CELL, Grid.CELL)), Color.WHITE, true)


## A block of spikes: a one-pixel base on the side that faces the bar and
## teeth standing out of it, away from the bar. The way out is the block's row
## side (down for the bottom row, up for the top) turned with the bar, taken as
## the nearest of the four directions.
func _teeth(at: Vector2, offset: Vector2) -> void:
	var out := Vector2(0, 1) if offset.y > 0.0 else Vector2(0, -1)
	out = out.rotated(path.angle_at(_tick))
	var dir := Vector2i(signi(roundi(out.x)), signi(roundi(out.y)))
	if absf(out.x) >= absf(out.y):
		dir = Vector2i(1 if out.x > 0.0 else -1, 0)
	else:
		dir = Vector2i(0, 1 if out.y > 0.0 else -1)
	for i in Grid.CELL:
		var height: int = TEETH[i]
		if dir.x == 0:
			var y0 := at.y + (float(Grid.CELL - 1 - height) if dir.y > 0 else 0.0)
			draw_rect(Rect2(Vector2(at.x + float(i), y0), Vector2(1, height + 1)), Color.WHITE)
			var base_y := at.y if dir.y > 0 else at.y + float(Grid.CELL - 1)
			draw_rect(Rect2(Vector2(at.x + float(i), base_y), Vector2.ONE), Color.WHITE)
		else:
			var x0 := at.x + (float(Grid.CELL - 1 - height) if dir.x > 0 else 0.0)
			draw_rect(Rect2(Vector2(x0, at.y + float(i)), Vector2(height + 1, 1)), Color.WHITE)
			var base_x := at.x if dir.x > 0 else at.x + float(Grid.CELL - 1)
			draw_rect(Rect2(Vector2(base_x, at.y + float(i)), Vector2.ONE), Color.WHITE)
