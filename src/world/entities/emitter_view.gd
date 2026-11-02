class_name EmitterView
extends Node2D

## An emitter's platforms as they are drawn: white blocks with a crack through
## each cell, like a breakable wall's look but whole. The room moves them each
## tick to where `EmitterPath` has them. A generation that ends bursts into
## shards at the track endpoint, even when its slot is immediately reused.
## Each is drawn on a whole world pixel, like a moving platform.

var path: EmitterPath
var _current: Array[Vector2] = []
var _previous: Array[Vector2] = []
var _alive: Array[bool] = []
var _tick := 0


func _init(emitter_path: EmitterPath, tick := 0) -> void:
	path = emitter_path
	_tick = tick
	name = "Emitter_%s" % path.id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for body in path.body_count():
		_current.append(path.rect_at(tick, body).position)
		_previous.append(_current[body])
		_alive.append(path.alive_at(tick, body))


## Puts every platform where its path has it at `tick`, in the room's space,
## and bursts any that have just broken.
func move_to(tick: int) -> void:
	if tick == _tick:
		return
	var elapsed := tick - _tick
	for body in path.body_count():
		var now := path.alive_at(tick, body)
		# Skipped forward samples preserve interpolation only within one life.
		# Show one break for the previously visible generation; do not replay
		# effects for generations never sampled. Rewinds reset without effects.
		var continuous := elapsed > 0 and path.continuous_at(_tick, body)
		continuous = continuous and path.age_at(tick, body) == path.age_at(_tick, body) + elapsed
		if elapsed > 0 and _alive[body] and not continuous and get_parent() != null:
			var size := Grid.cell_rect(path.start_cells).size
			var burst_at := Grid.cell_rect(path.start_cells).position + Vector2(path.direction) * path.distance()
			for cell in int(size.x / float(Grid.CELL)):
				var burst := Shatter.new()
				burst.position = burst_at + Vector2(float(cell * Grid.CELL) + Grid.CELL * 0.5, Grid.CELL * 0.5)
				get_parent().add_child(burst)
		var appeared := now and (not _alive[body] or not continuous)
		_alive[body] = now
		_previous[body] = _current[body]
		if now:
			_current[body] = path.rect_at(tick, body).position
			if appeared:
				_previous[body] = _current[body]
	_tick = tick
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Where platform `body` is drawn `fraction` of the way from the last tick to
## this one, on a whole world pixel.
func shown_at(body: int, fraction: float) -> Vector2:
	return Display.snap(_previous[body].lerp(_current[body], fraction))


func _draw() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	var size := Grid.cell_rect(path.start_cells).size
	for body in path.body_count():
		if not _alive[body]:
			continue
		var at := shown_at(body, fraction)
		draw_rect(Rect2(at, size), Color.WHITE, true)
		for cell in int(size.x / float(Grid.CELL)):
			_crack(at + Vector2(float(cell * Grid.CELL), 0.0), (cell + body) % 2 == 1)


## One jagged crack down a cell, a pixel wide.
func _crack(origin: Vector2, mirrored: bool) -> void:
	var points := [Vector2(3, 0), Vector2(4, 3), Vector2(2, 5), Vector2(5, 7), Vector2(4, 9)]
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if mirrored:
			a.x = 9.0 - a.x
			b.x = 9.0 - b.x
		var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
		for step in steps + 1:
			var pixel := a.lerp(b, float(step) / float(maxi(steps, 1))).round()
			draw_rect(Rect2(origin + pixel, Vector2.ONE), Color.BLACK)
