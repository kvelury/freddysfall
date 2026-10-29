class_name FreddySprites
extends RefCounted

## Freddy the frog, as the pictures `PlayerBody` draws. Every picture is 10
## pixels wide and sits in the player's 10 x 10 box, bottom to bottom, so none
## of it is wider than the collision box and the feet stand on the floor.
## Rows are characters from `COLOURS` (`#` body, `=` legs, `+` eyes, `o` black)
## or `EMPTY`, drawn facing right; facing left mirrors them. `top` is the box
## row of the picture's first row.
##
## The body is the same in every picture, so the inventory marks
## (`InventoryMarks`) land on body (`BODY_PIXEL`) wherever the legs are, and are
## cut from body only, never from the eyes or legs. Stalks are rows 0-1
## with the pupils in row 1, the front (right) is notched on rows 3-4, and the
## rear is the left edge the marks are cut one pixel inside of.

enum Pose { STAND, WALK, JUMP, LAND }

## What each character of a picture is drawn in. Each pixel is one character,
## so the colours never overlap and their order does not matter. Freddy is
## colour option 1 ("mono green") of the user's sheet: body and legs both lime,
## eyes white. The legs have their own character because the sheet's other
## options recolour only them: one of those is a change to `=` here.
const COLOURS: Dictionary[String, Color] = {
	"#": Color("c6fb65"),
	"=": Color("c6fb65"),
	"+": Color.WHITE,
	"o": Color.BLACK,
}
## A pixel that is not drawn.
const EMPTY := "."
## The pixels the inventory marks are cut from, and what a cut pixel becomes.
const BODY_PIXEL := "#"
const MARK_PIXEL := "o"

const BODY: Array[String] = [
	".+++...+++",
	".+o+...+o+",
	"##########",
	"########..",
	"########..",
	"##########",
	"##########",
	"##########",
]

const STAND_LEGS: Array[String] = [
	".==....==.",
	"===....===",
]

## The left leg lifts and swings forward and plants, then the right one does,
## while the planted foot slides back under the body. Two rows each, 8 -> 9.
## The walk is as many pictures as there are entries here (`walk_length`).
const WALK_LEGS: Array[PackedStringArray] = [
	[".==....==.", "===....==="],
	[".==...==..", "===...===."],
	[".==...==..", "......===."],
	["..==..==..", "......===."],
	["..==..==..", ".===..===."],
	["..==..==..", ".===......"],
	["..==...==.", ".===......"],
	[".==....==.", ".===...==="],
]

## Legs thrown out wide and tucked in at the tips.
const JUMP_LEGS: Array[String] = [
	"==......==",
	".==....==.",
]

## Squashed on landing: a low, wide frog, seven rows from row 3 down.
const LAND_TOP := 3
const LAND: Array[String] = [
	".+++...+++",
	".+o+...+o+",
	"##########",
	"########..",
	"##########",
	"##########",
	"===....===",
]

## Drawn pictures, by pose, step, facing and marks. They never change, so each
## is worked out once.
static var _drawn := {}


## One picture: its rows, and the box row its first row is on.
class Frame:
	var top: int
	var rows: PackedStringArray

	func _init(at: int, lines: Array) -> void:
		top = at
		rows = PackedStringArray(lines)


## A picture as rects from the box's top-left corner: one layer for each
## character of `COLOURS` it uses.
class Drawn:
	var layers: Array[Layer] = []

	## Every rect drawn in `colour`, from all the layers of that colour.
	func rects_in(colour: Color) -> Array[Rect2]:
		var out: Array[Rect2] = []
		for layer in layers:
			if layer.colour == colour:
				out.append_array(layer.rects)
		return out


## The pixels of one character of `COLOURS`, in its colour.
class Layer:
	var pixel: String
	var colour: Color
	var rects: Array[Rect2] = []


## How many pictures the walk has.
static func walk_length() -> int:
	return WALK_LEGS.size()


## The picture for `pose`; `step` picks the walk picture and wraps.
static func frame(pose: Pose, step := 0) -> Frame:
	match pose:
		Pose.WALK:
			return Frame.new(0, _stack(WALK_LEGS[posmod(step, walk_length())]))
		Pose.JUMP:
			return Frame.new(0, _stack(JUMP_LEGS))
		Pose.LAND:
			return Frame.new(LAND_TOP, LAND)
	return Frame.new(0, _stack(STAND_LEGS))


## Every picture the player can show, for checking them.
static func frames() -> Array[Frame]:
	var out: Array[Frame] = []
	for pose: Pose in Pose.values():
		for step in (walk_length() if pose == Pose.WALK else 1):
			out.append(frame(pose, step))
	return out


## What is wrong with the pictures: a row that is not the box's width, a
## character that is not a pixel, or a picture that leaves the box. Empty when
## they are right. `PlayerBody` reports these in a debug build.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for c in COLOURS:
		if c.length() != 1 or c == EMPTY:
			out.append("COLOURS key '%s' must be one character and not '%s'" % [c, EMPTY])
	if not COLOURS.has(BODY_PIXEL) or not COLOURS.has(MARK_PIXEL):
		out.append("COLOURS needs the body '%s' and the mark '%s'" % [BODY_PIXEL, MARK_PIXEL])
	var size := InventoryMarks.SIZE
	for pose: Pose in Pose.values():
		for step in (walk_length() if pose == Pose.WALK else 1):
			var picture := frame(pose, step)
			var name := "%s %d" % [Pose.keys()[pose], step]
			if picture.top < 0 or picture.top + picture.rows.size() > size:
				out.append("%s: rows %d to %d leave the %d-row box" % [name, picture.top, picture.top + picture.rows.size() - 1, size])
			for y in picture.rows.size():
				var row := picture.rows[y]
				if row.length() != size:
					out.append("%s row %d is %d wide, not %d" % [name, y, row.length(), size])
				for c in row:
					if c != EMPTY and not COLOURS.has(c):
						out.append("%s row %d has '%s', which is not %s or one of %s" % [name, y, c, EMPTY, COLOURS.keys()])
	return out


## The picture for `pose` and `step`, mirrored for `facing`, with `cut` (box
## pixels from `InventoryMarks`, already mirrored for `facing`) turned to
## `MARK_PIXEL` wherever the picture is `BODY_PIXEL`.
static func rects(pose: Pose, step: int, facing: int, cut: Array[Vector2i]) -> Drawn:
	if pose == Pose.WALK:
		step = posmod(step, walk_length())
	else:
		step = 0
	var key := "%d/%d/%d/%s" % [pose, step, signi(facing), cut]
	if not _drawn.has(key):
		_drawn[key] = _draw(frame(pose, step), facing, cut)
	return _drawn[key]


static func _draw(picture: Frame, facing: int, cut: Array[Vector2i]) -> Drawn:
	var rows := PackedStringArray()
	for row in picture.rows:
		rows.append(row.reverse() if facing < 0 else row)
	for p in cut:
		var y := p.y - picture.top
		if y < 0 or y >= rows.size() or rows[y][p.x] != BODY_PIXEL:
			continue
		rows[y] = rows[y].substr(0, p.x) + MARK_PIXEL + rows[y].substr(p.x + 1)
	var out := Drawn.new()
	for c in COLOURS:
		# PixelArt lights `#`, so each colour is drawn from rows with only its pixels lit.
		var only: Array = []
		for row in rows:
			var line := ""
			for ch in row:
				line += "#" if ch == c else EMPTY
			only.append(line)
		var layer := Layer.new()
		layer.pixel = c
		layer.colour = COLOURS[c]
		layer.rects = PixelArt.rects(only, Vector2i(0, picture.top))
		if not layer.rects.is_empty():
			out.layers.append(layer)
	return out


## The body with `legs` under it.
static func _stack(legs: Array) -> Array:
	var rows: Array = BODY.duplicate()
	rows.append_array(legs)
	return rows
