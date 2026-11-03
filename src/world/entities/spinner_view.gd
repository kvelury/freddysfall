class_name SpinnerView
extends Node2D

## A spinner's blocks as they are drawn: a white block for each safe cell and a
## row of spike teeth for each spiked one, pointing away from the middle of the
## bar. The room moves it each tick. Each block is drawn on a whole world pixel,
## like a moving platform.

var path: SpinnerPath
var _tick := 0
var _current: Array[Vector2] = []
var _previous: Array[Vector2] = []
## Whether any block moved on the last tick; _draw interpolates, so it has to
## run every frame while one does.
var _moving := false


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
	_moving = false
	for body in path.body_count():
		if _previous[body] != _current[body]:
			_moving = true
	queue_redraw()


func _process(_delta: float) -> void:
	if _moving:
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


## A block of spikes, drawn as the same teeth as a `^` cell, pointing away
## from the bar. The way out is facing_at().
func _teeth(at: Vector2, offset: Vector2) -> void:
	PixelArt.draw(self, PixelArt.spikes_name(facing_at(_tick, offset)), at)


## The way a spiked block's teeth point at `tick`: away from the bar, which is
## down for the bottom row and up for the top, turned with the bar and taken as
## the nearest of the four directions.
func facing_at(tick: int, offset: Vector2) -> Vector2i:
	var out := Vector2(0, 1) if offset.y > 0.0 else Vector2(0, -1)
	out = out.rotated(path.angle_at(tick))
	if absf(out.x) >= absf(out.y):
		return Vector2i.RIGHT if out.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if out.y > 0.0 else Vector2i.UP
