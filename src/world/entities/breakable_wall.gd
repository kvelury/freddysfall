class_name BreakableWall
extends Node2D

## A cracked wall that only the gun destroys. It is solid, so a player can
## stand on it like any platform, until enough hits have landed: then it shatters
## and is gone until the room is built again. Nothing about it is saved.
##
## It is drawn as one or more cells (the legend glyph is drawn on every cell of
## the wall; see RoomParser), in the room's own coordinates, so it sits at the
## room's origin. The room owns the collision: it asks `rects()` while the wall
## stands.

## Hits that break a wall unless a dev test says otherwise.
const DEFAULT_STRENGTH := 3
## How many steps of cracking are drawn between whole and broken.
const STAGES := 3

var def: EntityDef
var cells: Array[Vector2i] = []
## Hits taken so far.
var damage := 0
var broken := false
var _strength := DEFAULT_STRENGTH
var _flash := 0.0


func _init(entity: EntityDef = null) -> void:
	def = entity
	if entity != null:
		cells = entity.cells
	# Drawn in _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The wall's cells as pixel rects, relative to the room.
func local_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for cell in cells:
		out.append(Grid.cell_rect(Rect2i(cell, Vector2i.ONE)))
	return out


## The same, in world pixels.
func world_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in local_rects():
		out.append(Rect2(rect.position + global_position, rect.size))
	return out


## A shot lands. `strength` is how many it takes. Returns whether the wall
## broke, in which case it has already shattered and left the scene.
func hit(strength: int) -> bool:
	_strength = maxi(1, strength)
	damage += 1
	_flash = 0.07
	if damage >= _strength:
		broken = true
		for cell in cells:
			var burst := Shatter.new()
			burst.position = Grid.cell_center(cell)
			get_parent().add_child(burst)
		queue_free()
		return true
	queue_redraw()
	return false


## How cracked the wall looks, from 0 (the cracks it always has) to STAGES.
func stage() -> int:
	return clampi(ceili(float(damage) * float(STAGES) / float(_strength)), 0, STAGES)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


func _draw() -> void:
	var flashing := _flash > 0.0
	var ink := Color.WHITE if flashing else Color.BLACK
	var base := Color.BLACK if flashing else Color.WHITE
	for cell in cells:
		var origin := Grid.cell_to_world(cell)
		draw_rect(Rect2(origin, Vector2(Grid.CELL, Grid.CELL)), base)
		var variant := (cell.x * 7 + cell.y * 13) % 4
		for crack in stage() + 1:
			_crack(origin, (variant + crack * 2) % 4, crack, ink)


## One jagged crack across a cell, a pixel wide, as short straight runs. The
## shape depends on `variant` (0 to 3) so neighbouring cells do not tile;
## `crack` picks where the crack starts, so each stage adds new ones.
func _crack(origin: Vector2, variant: int, crack: int, ink: Color) -> void:
	var paths := [
		[Vector2(3, 0), Vector2(4, 3), Vector2(2, 5), Vector2(5, 7), Vector2(4, 9)],
		[Vector2(7, 0), Vector2(6, 2), Vector2(8, 4), Vector2(6, 7), Vector2(7, 9)],
		[Vector2(0, 4), Vector2(3, 5), Vector2(5, 4), Vector2(8, 6), Vector2(9, 5)],
		[Vector2(0, 7), Vector2(2, 6), Vector2(4, 8), Vector2(7, 7), Vector2(9, 9)],
	]
	var points: Array = paths[variant]
	if crack % 2 == 1:
		# A mirrored path, so a second crack in a cell is not a copy of the first.
		points = points.map(func(p: Vector2) -> Vector2: return Vector2(9.0 - p.x, p.y))
	for i in points.size() - 1:
		_line(origin, points[i], points[i + 1], ink)


## Pixels along a straight line between two points in a cell.
func _line(origin: Vector2, from: Vector2, to: Vector2, ink: Color) -> void:
	var steps := int(maxf(absf(to.x - from.x), absf(to.y - from.y)))
	for i in steps + 1:
		var at := from.lerp(to, float(i) / float(maxi(steps, 1))).round()
		draw_rect(Rect2(origin + at, Vector2.ONE), ink)
