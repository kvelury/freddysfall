class_name SpinnerPath
extends Mover

## A bar that turns about its middle, built of grid blocks. It is drawn as a
## rectangle of its glyph in the pose it starts in. Every cell is a body: a
## 10 x 10 block that turns with the bar. At each tick the turned bar is filled
## in on the world's pixels (a pixel is lit when its centre is inside it) as rows
## 1 px tall, so it is one straight edge, not steps, and what is drawn is exactly
## what is solid. Every pixel belongs to one cell, so neighbouring cells never
## gap or overlap. Blocks that are spiked kill on touch; the others are solid and
## carry a rider.
##
## It turns once in `period` seconds, counter-clockwise on screen unless the
## legend says `dir=cw`. Its angle is worked out from whole ticks, so the game
## and the solver agree.

## The parts of the bar `spikes=` can name, joined by + in the legend.
const SPIKE_NAMES: Array[String] = ["all", "top", "bottom", "left", "right", "top_left", "top_right", "bottom_left", "bottom_right"]
## The steepest a face can be, as the up component of its normal (cos 60 degrees),
## for a body to stand on it. A steeper one pushes a body off.
const STAND_COS := 0.5
## Cached ticks (one per tick of the turn) are dropped past this many.
const CACHE_LIMIT := 4096
## A line closer to vertical or horizontal than this is treated as exactly so.
const EPS := 1.0e-9

## The cells it is drawn on, in its starting pose.
var start_cells := Rect2i()
## The point every block goes round, in room pixels.
var pivot := Vector2.ZERO
var period_ticks := 1
var clockwise := false
## One entry per body, left to right then top to bottom: the block's centre
## relative to the pivot when it starts, and whether it is spiked.
var offsets: Array[Vector2] = []
var spiked: Array[bool] = []
## The farthest any corner of the bar gets from the pivot, in pixels.
var radius := 0.0
## For each body, the way its teeth point when the bar is in its starting pose
## (up for a top row, down for a bottom row, left or right for an end column),
## or zero for a body that is not spiked.
var normals: Array[Vector2] = []
## Whether the tongue breaks it (`breakable=true`). Hit enough times, every block
## of it goes and it is gone until the room is built again.
var breakable := false
## Whether it has been broken: a copy of a breakable spinner with no bodies
## standing. The game swaps it in when the last lash lands, and the solver
## solves a room with the arm broken as a copy of the room.
var gone := false
## The settings it was built from, so a broken copy can be made.
var _spikes := PackedStringArray()
## The bar as drawn, relative to the pivot, in the starting pose.
var _local := Rect2()
## The rows of pixels at a tick (`_frame`), kept by the tick within one turn.
var _frames := {}
var _teeth := {}


## `spikes` names the spiked blocks of the bar as drawn: "top" and "bottom" for
## a whole row, "top_left", "top_right", "bottom_left" and "bottom_right" for the
## half of that row on that side of the middle (the middle block is in neither),
## "left" and "right" for a whole end column, and "all".
##
## `pivot_at` is the point it turns about, in room pixels. Left out, it is the
## middle of the rectangle. Several spinners given the same point turn together,
## which is how a cross is built from arms and a hub.
func _init(spinner_id: String, drawn: Rect2i, seconds: float, turns_clockwise: bool, spikes: PackedStringArray, pivot_at := Vector2.INF, breakable_arm := false) -> void:
	id = spinner_id
	start_cells = drawn
	clockwise = turns_clockwise
	breakable = breakable_arm
	_spikes = spikes
	period_ticks = maxi(1, roundi(seconds * float(TICKS_PER_SECOND)))
	var box := Grid.cell_rect(drawn)
	pivot = box.get_center() if pivot_at == Vector2.INF else pivot_at
	_local = Rect2(box.position - pivot, box.size)
	var middle := (drawn.size.x - 1) / 2
	for row in drawn.size.y:
		for col in drawn.size.x:
			var cell := Grid.cell_rect(Rect2i(drawn.position + Vector2i(col, row), Vector2i.ONE))
			offsets.append(cell.get_center() - pivot)
			var top := row < drawn.size.y / 2.0
			var half := "left" if col < middle else ("right" if col > middle else "")
			var side := "top" if top else "bottom"
			var hit := spikes.has("all") or spikes.has(side)
			hit = hit or (not half.is_empty() and spikes.has("%s_%s" % [side, half]))
			var on_left := col == 0 and spikes.has("left")
			var on_right := col == drawn.size.x - 1 and spikes.has("right")
			hit = hit or on_left or on_right
			spiked.append(hit)
			# A row part points up or down; a block only an end column names points
			# out of that end. `all` goes by the row, as it always did.
			var row_part := spikes.has("all") or spikes.has(side) or (not half.is_empty() and spikes.has("%s_%s" % [side, half]))
			if not hit:
				normals.append(Vector2.ZERO)
			elif row_part or not (on_left or on_right):
				normals.append(Vector2.UP if top else Vector2.DOWN)
			else:
				normals.append(Vector2.LEFT if on_left else Vector2.RIGHT)
	for offset in offsets:
		for corner in [Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
			radius = maxf(radius, (offset + corner).length())


func body_count() -> int:
	return offsets.size()


func alive_at(_tick: int, _body := 0) -> bool:
	return not gone


## This spinner with every block gone (see `gone`). The same settings, so it has
## the same place in a room's list of movers, and nothing in it stands.
func broken_copy() -> SpinnerPath:
	var out := SpinnerPath.new(id, start_cells, float(period_ticks) / float(TICKS_PER_SECOND), clockwise, _spikes, pivot, breakable)
	out.gone = true
	return out


func is_hazard(body := 0) -> bool:
	return spiked[body]


func period() -> int:
	return period_ticks


## The cell body `body` is drawn on in the starting pose.
func start_cell_of(body: int) -> Vector2i:
	return start_cells.position + Vector2i(body % start_cells.size.x, body / start_cells.size.x)


## How far round it has turned at `tick`, in radians, positive being the way it
## turns (counter-clockwise on screen, which is negative in a y-down world).
func angle_at(tick: int) -> float:
	var turns := float(posmod(tick, period_ticks)) / float(period_ticks)
	return TAU * turns if clockwise else -TAU * turns


## The box round body `body` at `tick`: every pixel it is made of. Its pixels
## are `spans_at`.
func rect_at(tick: int, body := 0) -> Rect2:
	return _frame(tick)["bounds"][body]


func smooth() -> bool:
	return true


func spans_at(tick: int, body := 0) -> Array[Rect2]:
	if gone:
		return []
	return _frame(tick)["spans"][body]


## The turned bar at `tick` as rows of pixels: for each body its spans, and the
## box round them. The pixel rows between the tops and bottoms of the bar are
## each cut where the bar's edges and the lines between cells cross them, and a
## run belongs to the cell its middle is in. A pixel is in the run when its
## centre is, so the cut is the same number for the cells either side of it.
func _frame(tick: int) -> Dictionary:
	var at := posmod(tick, period_ticks)
	var found: Variant = _frames.get(at)
	if found != null:
		return found
	if _frames.size() >= CACHE_LIMIT:
		_frames.clear()
	var phi := angle_at(at)
	var cs := cos(phi)
	var sn := sin(phi)
	var cols := start_cells.size.x
	var rows := start_cells.size.y
	var cell := float(Grid.CELL)
	var spans: Array = []
	for body in body_count():
		var empty: Array[Rect2] = []
		spans.append(empty)
	var u0 := _local.position.x
	var v0 := _local.position.y
	# The rows the turned bar reaches: its corners' heights.
	var low := INF
	var high := -INF
	for corner in [Vector2(u0, v0), Vector2(u0 + _local.size.x, v0), Vector2(u0, v0 + _local.size.y), Vector2(u0 + _local.size.x, v0 + _local.size.y)]:
		var y: float = pivot.y + sn * corner.x + cs * corner.y
		low = minf(low, y)
		high = maxf(high, y)
	var first := floori(low) - 1
	var last := ceili(high) + 1
	for py in range(first, last):
		var dy := float(py) + 0.5 - pivot.y
		# The bar's own coordinates of the point (dx, dy) from the pivot are
		# u = cs * dx + sn * dy and v = -sn * dx + cs * dy.
		var cuts: Array[float] = []
		if absf(cs) > EPS:
			for k in cols + 1:
				cuts.append((u0 + float(k) * cell - sn * dy) / cs)
		if absf(sn) > EPS:
			for k in rows + 1:
				cuts.append((cs * dy - v0 - float(k) * cell) / sn)
		if cuts.size() < 2:
			continue
		cuts.sort()
		for i in cuts.size() - 1:
			var from := cuts[i]
			var to := cuts[i + 1]
			if to - from < EPS:
				continue
			var middle := (from + to) * 0.5
			var u := cs * middle + sn * dy
			var v := -sn * middle + cs * dy
			var col := floori((u - u0) / cell)
			var row := floori((v - v0) / cell)
			if col < 0 or col >= cols or row < 0 or row >= rows:
				continue
			var x0 := ceili(pivot.x + from - 0.5)
			var x1 := ceili(pivot.x + to - 0.5)
			if x1 <= x0:
				continue
			var list: Array[Rect2] = spans[row * cols + col]
			if not list.is_empty() and list[list.size() - 1].position.y == float(py) and list[list.size() - 1].end.x == float(x0):
				var last_run := list[list.size() - 1]
				list[list.size() - 1] = Rect2(last_run.position, Vector2(float(x1) - last_run.position.x, 1.0))
			else:
				list.append(Rect2(Vector2(float(x0), float(py)), Vector2(float(x1 - x0), 1.0)))
	var bounds: Array[Rect2] = []
	for body in body_count():
		var list: Array[Rect2] = spans[body]
		var box := Rect2(pivot + offsets[body].rotated(phi) - Vector2(5, 5), Vector2(Grid.CELL, Grid.CELL))
		if not list.is_empty():
			box = list[0]
			for run in list:
				box = box.merge(run)
		bounds.append(box)
	var frame := {"spans": spans, "bounds": bounds}
	_frames[at] = frame
	return frame


## The pixels of the teeth of spiked body `body` at `tick`, as runs: the same
## picture as a `^` cell, turned with the bar and sampled on the world's pixels,
## so the points aim along the bar's own turn and not the nearest of four ways.
## Only what is drawn: a spiked body kills on all of its `spans_at`.
func teeth_at(tick: int, body: int) -> Array[Rect2]:
	var at := posmod(tick, period_ticks)
	var key := at * 4096 + body
	var found: Variant = _teeth.get(key)
	if found != null:
		return found
	if _teeth.size() >= CACHE_LIMIT:
		_teeth.clear()
	var out: Array[Rect2] = []
	var phi := angle_at(at)
	var cs := cos(phi)
	var sn := sin(phi)
	var cell := float(Grid.CELL)
	var col := body % start_cells.size.x
	var row := body / start_cells.size.x
	var u_start := _local.position.x + float(col) * cell
	var v_start := _local.position.y + float(row) * cell
	var lit := _picture(normals[body])
	for run: Rect2 in _frame(at)["spans"][body]:
		var y: float = run.position.y
		var from := -1.0
		for i in int(run.size.x) + 1:
			var x := run.position.x + float(i)
			var on := false
			if i < int(run.size.x):
				var dx := x + 0.5 - pivot.x
				var dy := y + 0.5 - pivot.y
				var ix := clampi(floori(cs * dx + sn * dy - u_start), 0, Grid.CELL - 1)
				var iy := clampi(floori(-sn * dx + cs * dy - v_start), 0, Grid.CELL - 1)
				on = lit[iy * Grid.CELL + ix]
			if on and from < 0.0:
				from = x
			elif not on and from >= 0.0:
				out.append(Rect2(Vector2(from, y), Vector2(x - from, 1.0)))
				from = -1.0
	_teeth[key] = out
	return out


## Which of a cell's 10 x 10 pixels the spike picture with its points toward
## `normal` lights, in reading order.
static func _picture(normal: Vector2) -> PackedByteArray:
	var name := PixelArt.spikes_name(Vector2i(normal))
	var shape: Dictionary = PixelShapes.SHAPES[name]
	var lit := PackedByteArray()
	lit.resize(Grid.CELL * Grid.CELL)
	var offset: Vector2i = shape["offset"]
	var rows: Array = shape["rows"]
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			if line[x] == "#":
				lit[(offset.y + y) * Grid.CELL + offset.x + x] = 1
	return lit


## How far a body standing at `point` (room pixels) is carried by the bar from
## `tick` to `tick + 1`: the point going round the pivot.
func carry_at(tick: int, _body: int, point: Vector2) -> Vector2:
	if gone:
		return Vector2.ZERO
	var turn := angle_at(tick + 1) - angle_at(tick)
	return (point - pivot).rotated(turn) + pivot - point


## The top left corner of body `body` relative to the pivot, in the starting pose.
func local_origin_of(body: int) -> Vector2:
	var cell := float(Grid.CELL)
	return _local.position + Vector2(float(body % start_cells.size.x), float(body / start_cells.size.x)) * cell


## The centre of body `body` at `tick`.
func centre_at(tick: int, body: int) -> Vector2:
	return pivot + offsets[body].rotated(angle_at(tick))


## How far a 10 x 10 box centred on `centre` has to go to leave the turned block
## of body `body` at `tick`, along the axis it is least in the way of (the box's
## two or the block's two). The zero vector if they do not overlap.
func push_at(tick: int, body: int, centre: Vector2) -> Vector2:
	if gone:
		return Vector2.ZERO
	var phi := angle_at(tick)
	var along := Vector2(cos(phi), sin(phi))
	var across := Vector2(-along.y, along.x)
	var d := centre - centre_at(tick, body)
	var best := INF
	var out := Vector2.ZERO
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, along, across]:
		var reach := 5.0 * (absf(axis.x) + absf(axis.y)) + 5.0 * (absf(axis.dot(along)) + absf(axis.dot(across)))
		var gap := d.dot(axis)
		var overlap := reach - absf(gap)
		if overlap <= 0.0:
			return Vector2.ZERO
		if overlap < best:
			best = overlap
			out = axis * (overlap if gap >= 0.0 else -overlap)
	return out


## Whether a body can stand on body `body` at `tick`: one of its outer faces
## looks up within 60 degrees of straight up.
func rideable_at(tick: int, body: int) -> bool:
	if gone:
		return false
	var phi := angle_at(tick)
	var col := body % start_cells.size.x
	var row := body / start_cells.size.x
	var faces: Array[Vector2] = []
	if row == 0:
		faces.append(Vector2.UP)
	if row == start_cells.size.y - 1:
		faces.append(Vector2.DOWN)
	if col == 0:
		faces.append(Vector2.LEFT)
	if col == start_cells.size.x - 1:
		faces.append(Vector2.RIGHT)
	for face in faces:
		if -face.rotated(phi).y >= STAND_COS - 0.0001:
			return true
	return false


## The places a body can stand on body `body` at `tick`: the left end, the right
## end and the middle of its pixels, each with the top pixel row under a body
## there.
func stand_spots(tick: int, body := 0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not rideable_at(tick, body):
		return out
	var rect := rect_at(tick, body)
	var runs := spans_at(tick, body)
	var xs: Array[float] = [rect.position.x + 0.01, rect.get_center().x, rect.end.x - 0.01]
	for x in xs:
		var top := INF
		for run in runs:
			if run.position.x < x + 4.5 and run.end.x > x - 4.5:
				top = minf(top, run.position.y)
		if top < INF:
			out.append(Vector2(x, top))
	return out


## The cells its blocks can ever be in: the square round the pivot that holds
## the circle they sweep.
func swept_cells() -> Rect2i:
	var reach := ceili(radius / float(Grid.CELL))
	var middle := Vector2i((pivot / float(Grid.CELL)).floor())
	return Rect2i(middle - Vector2i(reach, reach), Vector2i(reach, reach) * 2 + Vector2i.ONE)


## Nothing stands above it in particular: a rider can be anywhere on its sweep.
func band_cells() -> Rect2i:
	return Rect2i()


func keep_out() -> Rect2:
	return Grid.cell_rect(swept_cells())


## Whether the cell `cell` is touched by the circle the bar sweeps.
func sweeps(cell: Vector2i) -> bool:
	var box := Grid.cell_rect(Rect2i(cell, Vector2i.ONE))
	var nearest := Vector2(clampf(pivot.x, box.position.x, box.end.x), clampf(pivot.y, box.position.y, box.end.y))
	return nearest.distance_to(pivot) < radius
