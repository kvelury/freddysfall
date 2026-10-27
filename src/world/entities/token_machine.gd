class_name TokenMachine
extends Node2D

## The 3TM, a machine that takes three tokens and gives an upgrade. The legend
## glyph marks the middle cell of its bottom row, and it fills 3 x 3 cells of
## open air above and beside that cell. Touching it with tokens feeds them in
## one by one; the slots that are filled stay filled, even across a save, and
## the third one makes it give the upgrade. After that it is spent.
##
## This script only draws and tracks the machine. The world runs the deposit,
## because it has to freeze the player and spend their tokens.

const COST := 3
const WIDTH := 30.0
const HEIGHT := 30.0
## Slot centres, from the middle of the bottom cell.
const SLOTS: Array[Vector2] = [Vector2(-9, -20), Vector2(0, -20), Vector2(9, -20)]

var def: EntityDef
## How many slots are filled.
var filled := 0
## Whether the player was already told how full it is, while touching it.
var noted := false
var _age := 0.0
var _flash := 0.0
var _dispensing := -1.0


func _init(entity: EntityDef = null, slots_filled := 0) -> void:
	def = entity
	filled = slots_filled
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The cells the machine fills, given the glyph's cell.
static func footprint(cell: Vector2i) -> Rect2i:
	return Rect2i(cell + Vector2i(-1, -2), Vector2i(3, 3))


## Room-local pixels that touch the machine.
static func touch_rect_for(cell: Vector2i) -> Rect2:
	return Rect2(Grid.cell_center(cell) + Vector2(-WIDTH * 0.5, -HEIGHT + float(Grid.CELL) * 0.5), Vector2(WIDTH, HEIGHT))


## The area that works the machine, in world pixels.
func rect() -> Rect2:
	return Rect2(global_position + Vector2(-WIDTH * 0.5, -HEIGHT + float(Grid.CELL) * 0.5), Vector2(WIDTH, HEIGHT))


var spent: bool:
	get:
		return filled >= COST


## The centre of slot `i`, in world pixels.
func slot_position(i: int) -> Vector2:
	return global_position + SLOTS[i]


## The middle of the dispenser mouth, in world pixels.
func mouth_position() -> Vector2:
	return global_position + Vector2(0, -3)


## Fills the next slot, with a flash and a burst.
func fill() -> void:
	var slot := filled
	filled += 1
	_flash = 0.25
	var burst := Shatter.new()
	burst.position = SLOTS[slot]
	add_child(burst)


## The machine gives its upgrade: it shakes and flashes three times. Returns
## when it has finished.
func dispense() -> void:
	_dispensing = 0.0
	await get_tree().create_timer(0.8, true, true).timeout
	_dispensing = -1.0
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	_flash = maxf(0.0, _flash - delta)
	if _dispensing >= 0.0:
		_dispensing += delta
	queue_redraw()


func _draw() -> void:
	var shake := 0.0
	var flashing := _flash > 0.0
	if _dispensing >= 0.0 and _dispensing < 0.5:
		shake = 1.0 if int(_dispensing / 0.05) % 2 == 0 else -1.0
	if _dispensing >= 0.0 and _dispensing < 0.6:
		flashing = int(_dispensing / 0.1) % 2 == 0
	var origin := Vector2(shake, 0.0)
	var dotted := spent and _dispensing < 0.0
	# The bar on top, with an opening for each token.
	if flashing:
		draw_rect(Rect2(origin + Vector2(-15, -25), Vector2(WIDTH, 10)), Color.WHITE)
	_frame(Rect2(origin + Vector2(-15, -25), Vector2(WIDTH, 10)), dotted)
	for i in SLOTS.size():
		var at := origin + SLOTS[i]
		var ink := Color.BLACK if flashing else Color.WHITE
		if i < filled:
			Token.draw_token(self, at, ink)
		else:
			PixelArt.draw(self, "slot", at, ink)
	# The square body, with a dithered face and a dark dispenser mouth.
	_frame(Rect2(origin + Vector2(-10, -15), Vector2(20, 20)), dotted)
	if not dotted:
		for y in range(-13, -5):
			for x in range(-8, 8):
				if (x + y) % 2 == 0:
					draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), Color.WHITE)
	draw_rect(Rect2(origin + Vector2(-5, -4), Vector2(10, 7)), Color.BLACK)
	_frame(Rect2(origin + Vector2(-5, -4), Vector2(10, 7)), dotted)


## A one pixel outline of `area`. `dotted` skips every other pixel, so a spent
## machine looks switched off.
func _frame(area: Rect2, dotted: bool) -> void:
	var x0 := int(area.position.x)
	var y0 := int(area.position.y)
	var x1 := x0 + int(area.size.x) - 1
	var y1 := y0 + int(area.size.y) - 1
	for x in range(x0, x1 + 1):
		for y in [y0, y1]:
			if not dotted or (x + y) % 2 == 0:
				draw_rect(Rect2(x, y, 1, 1), Color.WHITE)
	for y in range(y0 + 1, y1):
		for x in [x0, x1]:
			if not dotted or (x + y) % 2 == 0:
				draw_rect(Rect2(x, y, 1, 1), Color.WHITE)
