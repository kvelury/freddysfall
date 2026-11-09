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
## For a breakable arm: how cracked it looks (0 to BreakableWall.STAGES), and how
## long a lash has left it flashing.
var damage_stage := 0
var _flash := 0.0


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


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()
	elif _moving:
		queue_redraw()


## A lash landed on this arm, which now looks `stage` cracked.
func struck(stage: int) -> void:
	damage_stage = stage
	_flash = 0.07
	queue_redraw()


## The arm breaks: every block bursts where it is, and the view goes.
func shatter() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for body in path.body_count():
		var burst := Shatter.new()
		burst.position = shown_at(body, fraction) + Vector2(Grid.CELL, Grid.CELL) * 0.5
		get_parent().add_child(burst)
	queue_free()


func shown_at(body: int, fraction: float) -> Vector2:
	return Display.snap(_previous[body].lerp(_current[body], fraction))


func _draw() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for body in path.body_count():
		var at := shown_at(body, fraction)
		if path.is_hazard(body):
			_teeth(at, path.normals[body])
		elif path.breakable:
			BreakableWall.paint_cell(self, at, path.start_cell_of(body), damage_stage, _flash > 0.0)
		else:
			draw_rect(Rect2(at, Vector2(Grid.CELL, Grid.CELL)), Color.WHITE, true)


## A block of spikes, drawn as the same teeth as a `^` cell, pointing away
## from the bar. The way out is facing_at().
func _teeth(at: Vector2, normal: Vector2) -> void:
	PixelArt.draw(self, PixelArt.spikes_name(facing_at(_tick, normal)), at)


## The way a spiked block's teeth point at `tick`: `normal` is the way they point
## in the starting pose (SpinnerPath.normals), turned with the bar and taken as
## the nearest of the four directions.
func facing_at(tick: int, normal: Vector2) -> Vector2i:
	var out := normal.rotated(path.angle_at(tick))
	if absf(out.x) >= absf(out.y):
		return Vector2i.RIGHT if out.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if out.y > 0.0 else Vector2i.UP
