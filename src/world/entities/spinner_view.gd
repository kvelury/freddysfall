class_name SpinnerView
extends Node2D

## A spinner as it is drawn: the pixels of the turned bar at this tick, which are
## exactly the pixels that are solid (`SpinnerPath.spans_at`). A safe block is
## white; a spiked one has the teeth of a `^` cell, turned with the bar. The room
## moves it each tick. Nothing is drawn between ticks, so the picture on screen
## is always what the physics sees, on whole world pixels.

var path: SpinnerPath
var _tick := 0
## For a breakable arm: how cracked it looks (0 to BreakableWall.STAGES), and how
## long a lash has left it flashing.
var damage_stage := 0
var _flash := 0.0


func _init(spinner_path: SpinnerPath, tick := 0) -> void:
	path = spinner_path
	name = "Spinner_%s" % path.id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_tick = tick


func move_to(tick: int) -> void:
	_tick = tick
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


## A lash landed on this arm, which now looks `stage` cracked.
func struck(stage: int) -> void:
	damage_stage = stage
	_flash = 0.07
	queue_redraw()


## The arm breaks: every block bursts where it is, and the view goes.
func shatter() -> void:
	for body in path.body_count():
		var burst := Shatter.new()
		burst.position = Display.snap(path.centre_at(_tick, body))
		get_parent().add_child(burst)
	queue_free()


func _draw() -> void:
	var flashing := _flash > 0.0
	var base := Color.BLACK if flashing and path.breakable else Color.WHITE
	for body in path.body_count():
		if path.is_hazard(body):
			for run in path.teeth_at(_tick, body):
				draw_rect(run, Color.WHITE)
			continue
		for run in path.spans_at(_tick, body):
			draw_rect(run, base)
		if path.breakable:
			_cracks(body, flashing)


## The cracks of a breakable arm's block `body`: the pixels of the picture a
## straight block would show, turned with the bar.
func _cracks(body: int, flashing: bool) -> void:
	var ink := Color.WHITE if flashing else Color.BLACK
	var phi := path.angle_at(_tick)
	var cell := float(Grid.CELL)
	var origin := path.local_origin_of(body)
	for at in BreakableWall.crack_pixels(path.start_cell_of(body), damage_stage):
		var local := origin + Vector2(at) + Vector2(0.5, 0.5)
		var pixel := path.pivot + local.rotated(phi)
		draw_rect(Rect2(Vector2(floorf(pixel.x), floorf(pixel.y)), Vector2.ONE), ink)
