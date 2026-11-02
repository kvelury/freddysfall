class_name EmitterView
extends Node2D

## An emitter's platforms as they are drawn: white blocks with a crack through
## each cell, like a breakable wall's look but whole. The room moves them each
## tick to where `EmitterPath` has them. A platform that breaks (its slot goes
## from there to not there) bursts into shards where it was. Each is drawn on a
## whole world pixel, like a moving platform.

var path: EmitterPath
var _current: Array[Vector2] = []
var _previous: Array[Vector2] = []
var _alive: Array[bool] = []


func _init(emitter_path: EmitterPath, tick := 0) -> void:
	path = emitter_path
	name = "Emitter_%s" % path.id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for body in path.body_count():
		_current.append(path.rect_at(tick, body).position)
		_previous.append(_current[body])
		_alive.append(path.alive_at(tick, body))


## Puts every platform where its path has it at `tick`, in the room's space,
## and bursts any that have just broken.
func move_to(tick: int) -> void:
	for body in path.body_count():
		var now := path.alive_at(tick, body)
		if _alive[body] and not now and get_parent() != null:
			var size := Grid.cell_rect(path.start_cells).size
			var burst_at := _current[body]
			for cell in int(size.x / float(Grid.CELL)):
				var burst := Shatter.new()
				burst.position = burst_at + Vector2(float(cell * Grid.CELL) + Grid.CELL * 0.5, Grid.CELL * 0.5)
				get_parent().add_child(burst)
		var appeared := now and not _alive[body]
		_alive[body] = now
		_previous[body] = _current[body]
		if now:
			_current[body] = path.rect_at(tick, body).position
			if appeared:
				_previous[body] = _current[body]
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
