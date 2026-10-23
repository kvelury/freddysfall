class_name SaveMachine
extends Node2D

## The save machine in a save room: a ring with a dark centre. Walking into it
## stops the player for SAVE_TIME while the ring lights one segment at a time and
## then the centre fills. The world does the rest (it sets the flag, saves, and
## says so), because that needs the player and the game's state.
##
## It fills 3 x 3 cells like a 3TM and its legend glyph marks the middle of the
## bottom row, so on a floor the glyph goes in the cell just above the floor.
## Once lit it stays lit until the room is left. Touching it again, after
## stepping off, saves again.

## How long the player is held while it lights.
const SAVE_TIME := 1.0
## The ring is lit in this many segments, and the centre fills after the last.
const SEGMENTS := 8
## The ring's middle, from the middle of the glyph's cell, and its radii in pixels.
const CENTRE := Vector2(0, -10)
const OUTER := 13.0
const INNER := 8.0
const HOLE := 4.0

var def: EntityDef
## Whether the player is still standing in it since it last worked, so that
## staying put does not save over and over.
var noted := false
## How many ring segments are lit, and whether the centre is filled.
var segments := 0
var core := false


func _init(entity: EntityDef = null) -> void:
	def = entity
	# It is redrawn from _process, so interpolation would have nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The key in the player's flags that says this machine has been used.
static func flag_for(entity: EntityDef) -> String:
	return "save:" + entity.id


## The cells it fills, given the glyph's cell. The same shape as a 3TM.
static func footprint(cell: Vector2i) -> Rect2i:
	return TokenMachine.footprint(cell)


## Room-local pixels that touch it, given the glyph's cell.
static func touch_rect_for(cell: Vector2i) -> Rect2:
	return TokenMachine.touch_rect_for(cell)


## The area that works it, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position + Vector2(-TokenMachine.WIDTH * 0.5, -TokenMachine.HEIGHT + float(Grid.CELL) * 0.5), Vector2(TokenMachine.WIDTH, TokenMachine.HEIGHT))


var lit: bool:
	get:
		return segments >= SEGMENTS and core


## Lights it all at once, for a player who was put on it by a respawn or a load.
func settle() -> void:
	noted = true
	segments = SEGMENTS
	core = true
	queue_redraw()


## Lights the ring a segment at a time, then the centre. Returns when it is
## done, SAVE_TIME later.
func light() -> void:
	segments = 0
	core = false
	var step := SAVE_TIME / float(SEGMENTS + 2)
	for i in SEGMENTS:
		await get_tree().create_timer(step, true, true).timeout
		segments = i + 1
		queue_redraw()
	await get_tree().create_timer(step * 2.0, true, true).timeout
	core = true
	queue_redraw()


## Switches the light off, for a machine about to be used again.
func dim() -> void:
	segments = 0
	core = false
	queue_redraw()


func _draw() -> void:
	# A one pixel outline of the ring and of the hole when dark. Each lit
	# segment fills the band between them.
	for y in range(-24, 5):
		for x in range(-14, 14):
			var at := Vector2(x, y) + Vector2(0.5, 0.5) - CENTRE
			var d := at.length()
			if d > OUTER:
				continue
			var segment := int(fmod(at.angle() + PI * 2.5, TAU) / (TAU / float(SEGMENTS)))
			var on := false
			if d >= OUTER - 1.0 or (d >= HOLE - 0.5 and d < HOLE + 0.5 and not core):
				on = true
			elif d >= INNER and segment < segments:
				on = true
			elif d < HOLE + 0.5 and core:
				on = true
			if on:
				draw_rect(Rect2(x, y, 1, 1), Color.WHITE)
	draw_rect(Rect2(-6, 3, 12, 2), Color.WHITE)
