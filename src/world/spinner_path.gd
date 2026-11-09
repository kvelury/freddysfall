class_name SpinnerPath
extends Mover

## A bar that turns about its middle, built of grid blocks. It is drawn as a
## rectangle of its glyph in the pose it starts in. Every cell is a body: a
## 10 x 10 block whose centre goes round the pivot, snapped to a whole pixel, so
## each block is still an axis-aligned rect and the physics and the solver need
## nothing new. Blocks that are spiked kill on touch; the others are solid and
## carry a rider.
##
## It turns once in `period` seconds, counter-clockwise on screen unless the
## legend says `dir=cw`. Its angle is worked out from whole ticks, so the game
## and the solver agree.

## The parts of the bar `spikes=` can name, joined by + in the legend.
const SPIKE_NAMES: Array[String] = ["all", "top", "bottom", "left", "right", "top_left", "top_right", "bottom_left", "bottom_right"]

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


func rect_at(tick: int, body := 0) -> Rect2:
	var centre := pivot + offsets[body].rotated(angle_at(tick))
	return Rect2(Display.snap(centre - Vector2(5, 5)), Vector2(Grid.CELL, Grid.CELL))


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
