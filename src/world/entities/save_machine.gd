class_name SaveMachine
extends Node2D

## The save machine in a save room: a sphere split into two halves, hinged at
## the bottom and standing open. A player who enters its zone is hopped into
## the middle, the halves close on them and spin, the game saves, and it opens
## and pops them out on the far side. The world does the moving and the saving,
## because that needs the player and the game's state; this draws the sphere and
## times its parts.
##
## It works once each time the room is entered: afterwards it stays closed until
## the room is left, so the player is never stopped twice and can see it is done.
## The room is rebuilt on every entry, so a new visit finds it open and unused.
##
## It fills 3 x 3 cells like a 3TM and its legend glyph marks the middle of the
## bottom row, so on a floor the glyph goes in the cell just above the floor. Its
## zone is the 3 x 3 and one more cell on each side, and the player is popped
## out onto the floor at the edge of that.

## The parts of a save, which add up to SAVE_TIME.
const HOP_TIME := 0.2
const CLOSE_TIME := 0.1
const SPIN_TIME := 0.6
const OPEN_TIME := 0.1
const POP_TIME := 0.2
const SAVE_TIME := HOP_TIME + CLOSE_TIME + SPIN_TIME + OPEN_TIME + POP_TIME
## How high above a straight line the player's hop and pop rise, in pixels.
const ARC_HEIGHT := 14.0

## The zone that starts a save, in pixels from the glyph's cell middle.
const ZONE_WIDTH := 50.0
const ZONE_HEIGHT := 30.0
## The sphere's radius in pixels. It is one pixel wider than twice this.
const RADIUS := 12
## How far each half swings from shut when open, in radians (about 29 degrees).
const OPEN_ANGLE := 0.5
## The pixel row of the hinge, the lowest pixel of the sphere: the one on the floor.
const HINGE_ROW := 4
## The sphere is shaded all over with close horizontal lines, one every
## LINE_STEP pixel rows: shading made of lines, not dots, so it never looks like
## a door's dithered halo.
const LINE_STEP := 2

var def: EntityDef
## Whether it has worked since the room was entered.
var used := false
## How open it is, from 0 (shut) to 1, and how far round it has turned while shut.
var openness := 1.0:
	set(value):
		openness = value
		queue_redraw()
var phase := 0.0:
	set(value):
		phase = value
		queue_redraw()


func _init(entity: EntityDef = null) -> void:
	def = entity
	# It is redrawn when it changes, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The key in the player's flags that says this machine has been used.
static func flag_for(entity: EntityDef) -> String:
	return "save:" + entity.id


## The cells it fills, given the glyph's cell. The same shape as a 3TM.
static func footprint(cell: Vector2i) -> Rect2i:
	return TokenMachine.footprint(cell)


## The cells of its zone: the 3 x 3 and a cell more each side. They are open air.
static func zone(cell: Vector2i) -> Rect2i:
	return Rect2i(cell + Vector2i(-2, -2), Vector2i(5, 3))


## The cell a player is popped out onto, on the left (-1) or the right (1).
static func landing(cell: Vector2i, side: int) -> Vector2i:
	return cell + Vector2i(2 * side, 0)


## Room-local pixels that start a save, given the glyph's cell.
static func touch_rect_for(cell: Vector2i) -> Rect2:
	return Rect2(Grid.cell_center(cell) + Vector2(-ZONE_WIDTH * 0.5, -ZONE_HEIGHT + float(Grid.CELL) * 0.5), Vector2(ZONE_WIDTH, ZONE_HEIGHT))


## The area that starts a save, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position + Vector2(-ZONE_WIDTH * 0.5, -ZONE_HEIGHT + float(Grid.CELL) * 0.5), Vector2(ZONE_WIDTH, ZONE_HEIGHT))


## The 3 x 3 cells it fills, in world pixels. A body in this is inside it.
func footprint_rect() -> Rect2:
	return Rect2(global_position + Vector2(-TokenMachine.WIDTH * 0.5, -TokenMachine.HEIGHT + float(Grid.CELL) * 0.5), Vector2(TokenMachine.WIDTH, TokenMachine.HEIGHT))


## The middle of the sphere, in world pixels, where the player is while it is shut.
func centre() -> Vector2:
	return global_position + Vector2(0.5, float(HINGE_ROW - RADIUS) + 0.5)


## Closes it at once, and leaves it that way.
func shut() -> void:
	openness = 0.0
	phase = 0.0


func close() -> void:
	await _ease("openness", 0.0, CLOSE_TIME)


## Turns it once round while it is shut.
func spin() -> void:
	phase = 0.0
	await _ease("phase", TAU, SPIN_TIME)
	phase = 0.0


func open() -> void:
	await _ease("openness", 1.0, OPEN_TIME)


func _ease(property: String, to: float, time: float) -> void:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, property, to, time)
	await tween.finished


func _draw() -> void:
	for pixel in pixels(openness, phase):
		draw_rect(Rect2(pixel.x, pixel.y, 1, 1), Color.WHITE)


## The pixels of the outline, from the glyph's cell middle. `open` is how far
## open it is (0 to 1). Shut, `turn` is how far round it has gone: the seam is a
## line down the middle at 0, and rounds the ball as it grows.
static func pixels(open: float, turn: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if open <= 0.0:
		for pixel in _shut(turn):
			out.append(pixel + Vector2i(0, HINGE_ROW))
	else:
		for pixel in _open(open * OPEN_ANGLE):
			out.append(pixel + Vector2i(0, HINGE_ROW))
	return out


## Pixels are given with the hinge at (0, 0), x across and y up as negatives.
static func _disc() -> Dictionary:
	var disc := {}
	for y in range(-2 * RADIUS, 1):
		for x in range(-RADIUS, RADIUS + 1):
			if x * x + (y + RADIUS) * (y + RADIUS) <= RADIUS * RADIUS:
				disc[Vector2i(x, y)] = true
	return disc


static func _shut(turn: float) -> Array[Vector2i]:
	var disc := _disc()
	var out := {}
	for pixel in disc:
		if _edge(disc, pixel) or _shade(pixel):
			out[pixel] = true
	# Four lines of longitude: the ones facing the front are drawn.
	for y in range(-2 * RADIUS, 1):
		var wide := sqrt(float(RADIUS * RADIUS - (y + RADIUS) * (y + RADIUS)))
		for k in 4:
			var angle := turn + float(k) * PI * 0.5
			if cos(angle) > 0.01:
				var pixel := Vector2i(roundi(wide * sin(angle)), y)
				if disc.has(pixel):
					out[pixel] = true
	var list: Array[Vector2i] = []
	list.assign(out.keys())
	return list


## Two half discs, each swung about the hinge by `angle`. The left one's edge is
## its whole outline; the right one's skips pixels the left one fills, so shut
## they share one line down the middle. Anything below the floor is cut.
static func _open(angle: float) -> Array[Vector2i]:
	var left := _half(-1, angle)
	var right := _half(1, angle)
	var list: Array[Vector2i] = []
	for pixel in left:
		if _edge(left, pixel) or _shade(pixel):
			list.append(pixel)
	for pixel in right:
		if _edge(right, pixel, left) or _shade(pixel):
			list.append(pixel)
	return list


static func _half(side: int, angle: float) -> Dictionary:
	var half := {}
	for y in range(-2 * RADIUS - 2, 1):
		for x in range(-2 * RADIUS, 2 * RADIUS + 1):
			var back := Vector2(x, y).rotated(-float(side) * angle)
			var from_middle := back - Vector2(0, -RADIUS)
			if from_middle.length_squared() <= float(RADIUS * RADIUS) and back.x * float(side) > -0.5:
				half[Vector2i(x, y)] = true
	return half


## Whether a pixel is one of the lines inside the sphere. The lines stay level
## on screen, even across a half that is swung open: tilted lines this close
## together break up into a checkerboard.
static func _shade(pixel: Vector2i) -> bool:
	return posmod(pixel.y, LINE_STEP) == 0


## Whether `pixel` is on the edge of `set`: a side of it is not in the set (nor,
## when `other` is given, in that one).
static func _edge(set: Dictionary, pixel: Vector2i, other := {}) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var next: Vector2i = pixel + step
		if not set.has(next) and not other.has(next):
			return true
	return false
