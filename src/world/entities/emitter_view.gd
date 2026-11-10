class_name EmitterView
extends Node2D

## An emitter's platforms as they are drawn: white blocks with a crack through
## each cell, like a breakable wall's look but whole. The room moves them each
## tick to where `EmitterPath` has them. A platform that breaks (its slot goes
## from there to not there) bursts into shards where it was. Each is drawn on a
## whole world pixel, like a moving platform. A `breakable` emitter's bodies (the
## pillars the tongue breaks) are painted cell by cell as a breakable wall is,
## with its cracks for each hit and its flash; whether one is there comes from the
## room's `Movers`, which knows the ones the tongue has broken.

var path: EmitterPath
var _current: Array[Vector2] = []
var _previous: Array[Vector2] = []
var _alive: Array[bool] = []
## How cracked each body looks (a breakable emitter's), and how long a lash has
## left it flashing.
var _stage: Array[int] = []
var _flash: Array[float] = []
## The room's movers and this emitter's first body in them, or null (then only
## the path says whether a body is there).
var _movers: Movers
var _first := 0
## Whether any platform moved on the last tick. _draw reads the physics
## interpolation fraction, so it has to run every frame while one is moving,
## and not at all when every platform stands still.
var _moving := false


func _init(emitter_path: EmitterPath, tick := 0, movers: Movers = null, first := 0) -> void:
	path = emitter_path
	_movers = movers
	_first = first
	name = "Emitter_%s" % path.id
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for body in path.body_count():
		_current.append(path.rect_at(tick, body).position)
		_previous.append(_current[body])
		_alive.append(_there(tick, body))
		_stage.append(0)
		_flash.append(0.0)


func _there(tick: int, body: int) -> bool:
	if _movers != null:
		return _movers.alive(_first + body, tick)
	return path.alive_at(tick, body)


## Puts every platform where its path has it at `tick`, in the room's space,
## and bursts any that have just broken.
func move_to(tick: int) -> void:
	for body in path.body_count():
		var now := _there(tick, body)
		if _alive[body] and not now and get_parent() != null:
			_burst(body)
		var appeared := now and not _alive[body]
		_alive[body] = now
		_previous[body] = _current[body]
		if now:
			_current[body] = path.rect_at(tick, body).position
			if appeared:
				_previous[body] = _current[body]
				_stage[body] = 0
				_flash[body] = 0.0
	_moving = false
	for body in path.body_count():
		if _alive[body] and _previous[body] != _current[body]:
			_moving = true
	queue_redraw()


## Shards out of every cell of platform `body`, where it was.
func _burst(body: int) -> void:
	var size := Grid.cell_rect(path.start_cells).size
	for row in int(size.y / float(Grid.CELL)):
		for cell in int(size.x / float(Grid.CELL)):
			var burst := Shatter.new()
			burst.position = _current[body] + Vector2(float(cell * Grid.CELL) + Grid.CELL * 0.5, float(row * Grid.CELL) + Grid.CELL * 0.5)
			get_parent().add_child(burst)


## A lash landed on body `body`, which now looks `stage` cracked.
func struck(body: int, stage: int) -> void:
	_stage[body] = stage
	_flash[body] = 0.07
	queue_redraw()


func _process(delta: float) -> void:
	var flashing := false
	for body in _flash.size():
		if _flash[body] > 0.0:
			_flash[body] = maxf(0.0, _flash[body] - delta)
			flashing = true
	if _moving or flashing:
		queue_redraw()


## Where platform `body` is drawn `fraction` of the way from the last tick to
## this one, on a whole world pixel.
func shown_at(body: int, fraction: float) -> Vector2:
	return Display.snap(_previous[body].lerp(_current[body], fraction))


func _draw() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	var size := Grid.cell_rect(path.start_cells).size
	var columns := int(size.x / float(Grid.CELL))
	var rows := int(size.y / float(Grid.CELL))
	for body in path.body_count():
		if not _alive[body]:
			continue
		var at := shown_at(body, fraction)
		if path.breakable:
			for row in rows:
				for cell in columns:
					var key := path.start_cells.position + Vector2i(cell + body * 3, row)
					BreakableWall.paint_cell(self, at + Vector2(cell, row) * float(Grid.CELL), key, _stage[body], _flash[body] > 0.0)
			continue
		draw_rect(Rect2(at, size), Color.WHITE, true)
		for row in rows:
			for cell in columns:
				_crack(at + Vector2(float(cell * Grid.CELL), float(row * Grid.CELL)), (cell + row + body) % 2 == 1)


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
