class_name FreddySprites
extends RefCounted

## Freddy the frog, as the pictures `PlayerBody` draws. Every picture is 10
## pixels wide and sits in the player's 10 x 10 box, bottom to bottom, so none
## of it is wider than the collision box and the feet stand on the floor.
## Rows are characters from `COLOURS` (`#` body, `y` the yellow patch on his
## front flank, `=` legs, `+` eyes, `o` black)
## or `EMPTY`, drawn facing right; facing left mirrors them. `top` is the box
## row of the picture's first row.
##
## Each pose (`PlayerAnimator.Pose`) has one animation, a `Clip`, in a table
## (`animation`): its pictures, and how they play. A picture says where the
## inventory marks (`InventoryMarks`) are cut from it, so a short picture keeps
## its marks. They are cut from body only (`BODY_PIXELS`: the lime and the patch), never from the eyes or
## legs. Stalks are rows 0-1 with the pupils in row 1, the front (right) is
## notched on row 3 (the mouth, where the tongue comes out; `Frame.mouth`), and
## the rear is the left edge the marks are cut one pixel inside of.
##
## To add an animation: a value in `PlayerAnimator.Pose`, one rule for it in
## `PlayerAnimator.advance`, and one row in `_build`.

## The box every picture is drawn in, in pixels: the player's 10 x 10 collision box.
const SIZE := Grid.CELL

## What each character of a picture is drawn in. Each pixel is one character,
## so the colours never overlap and their order does not matter. Freddy is
## colour option 1 ("mono green") of the user's sheet: body and legs both lime,
## eyes white. The legs have their own character because the sheet's other
## options recolour only them: one of those is a change to `=` here.
const COLOURS: Dictionary[String, Color] = {
	"#": Color("c6fb65"),
	# The patch on his front flank, in the user's drawing. The drawing was a screen
	# capture on a Display P3 screen (its lime read #D1FA7B for this #C6FB65), so
	# this is the sRGB colour that shows as the drawing's yellow there.
	"y": Color("f6ec00"),
	"=": Color("c6fb65"),
	"+": Color.WHITE,
	"o": Color.BLACK,
}
## A pixel that is not drawn.
const EMPTY := "."
## The pixels the inventory marks are cut from (body and patch), and what a cut
## pixel becomes.
const BODY_PIXELS := "#y"
const MARK_PIXEL := "o"

const BODY: Array[String] = [
	".+++...+++",
	".+o+...+o+",
	"##########",
	"########..",
	"######yyyy",
	"######yyyy",
	"######yyyy",
	"######yyyy",
]

const STAND_LEGS: Array[String] = [
	".==....==.",
	"===....===",
]

## The left leg lifts and swings forward and plants, then the right one does,
## while the planted foot slides back under the body. Two rows each, 8 -> 9.
## The walk is as many pictures as there are entries here.
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
const LAND: Array[String] = [
	".+++...+++",
	".+o+...+o+",
	"##########",
	"########..",
	"######yyyy",
	"######yyyy",
	"===....===",
]

## Looking up with the mouth open on top, for the tongue going up: the pupils
## are in the top row, and the notch (cols 4 and 5 of row 2) is the mouth.
const LASH_UP_BODY: Array[String] = [
	".+o+...+o+",
	".+++...+++",
	"####..####",
	"##########",
	"######yyyy",
	"######yyyy",
	"######yyyy",
	"######yyyy",
]
## The tongue comes out of the notch in that picture: its left column and its row.
const LASH_UP_MOUTH := Vector2i(4, 2)

## Where the inventory is cut on the standing body, facing right, in box pixels:
## the left pixel of each token's 2 x 1 line in the order they are filled (two
## stacked on the rear, one clear row between, then the third in the middle level
## with the gap, so no mark is up by the eyes), and the Imprint line along the
## last row of the belly, one clear row under the third.
const STAND_TOKENS: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 4), Vector2i(4, 5)]
const STAND_LINE: Array[Vector2i] = [Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7)]
## Landing is short: up to two tokens, the bottom one above the rear foot, and no line.
const LAND_TOKENS: Array[Vector2i] = [Vector2i(1, 8), Vector2i(1, 6)]
const LAND_LINE: Array[Vector2i] = []

## The animation of each pose, built on first use. It never changes.
static var _animations := {}
## Drawn pictures, by pose, picture, facing, tokens and Imprint. They never
## change, so each is worked out once.
static var _drawn := {}


## One picture: its rows, and the box row its first row is on.
class Frame:
	var top: int
	var rows: PackedStringArray
	## Where the inventory is cut on this picture, facing right, in box pixels.
	## `tokens`: the left pixel of each 2 x 1 token line, bottom first; fewer
	## than three hides the rest. `line`: the Imprint line's pixels; empty hides it. (`PlayerBody` does not draw it at present.)
	var tokens: Array[Vector2i] = []
	var line: Array[Vector2i] = []
	## The box row of the mouth: the notch at the front of the body, which is
	## the row whose last two pixels are empty under a body pixel. -1 if there is none.
	var mouth := -1
	## For a picture with the mouth on top: the notch's left column and its row,
	## where the tongue goes up from. (-1, -1) if there is none.
	var mouth_up := Vector2i(-1, -1)

	func _init(at: int, lines: Array, token_slots: Array[Vector2i], line_pixels: Array[Vector2i], up_mouth := Vector2i(-1, -1)) -> void:
		top = at
		mouth_up = up_mouth
		rows = PackedStringArray(lines)
		tokens = token_slots
		line = line_pixels
		for y in rows.size():
			var row := rows[y]
			if row.length() == SIZE and row.ends_with("..") and row[SIZE - 3] in BODY_PIXELS:
				mouth = at + y
				break


## How one pose's pictures play: an animation (not named that, as the engine has a class of that name).
class Clip:
	var frames: Array[Frame] = []
	## px of ground run per picture (`by_distance`), or seconds per picture. 0: the first picture only.
	var every := 0.0
	var by_distance := false
	var loop := true

	## The picture index for this long in the pose.
	func index(time: float, distance: float) -> int:
		if every <= 0.0 or frames.size() == 1:
			return 0
		var i := int((distance if by_distance else time) / every)
		return posmod(i, frames.size()) if loop else mini(i, frames.size() - 1)


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


## How `pose` plays. The table is the one place that says how many pictures a
## pose has and how fast they go.
static func animation(pose: PlayerAnimator.Pose) -> Clip:
	if _animations.is_empty():
		_animations = _build()
	return _animations.get(pose)


static func _build() -> Dictionary:
	var walk: Array[Frame] = []
	for legs in WALK_LEGS:
		walk.append(_standing(legs))
	var table := {}
	table[PlayerAnimator.Pose.STAND] = _animation([_standing(STAND_LEGS)])
	table[PlayerAnimator.Pose.WALK] = _animation(walk, 6.0, true)
	table[PlayerAnimator.Pose.JUMP] = _animation([_standing(JUMP_LEGS)])
	table[PlayerAnimator.Pose.LAND] = _animation([Frame.new(3, LAND, LAND_TOKENS, LAND_LINE)])
	var lash_up_rows: Array = LASH_UP_BODY.duplicate()
	lash_up_rows.append_array(STAND_LEGS)
	table[PlayerAnimator.Pose.LASH_UP] = _animation([Frame.new(0, lash_up_rows, STAND_TOKENS, STAND_LINE, LASH_UP_MOUTH)])
	return table


static func _animation(frames: Array[Frame], every := 0.0, by_distance := false) -> Clip:
	var out := Clip.new()
	out.frames = frames
	out.every = every
	out.by_distance = by_distance
	return out


## The body with `legs` under it, and the standing marks.
static func _standing(legs: Array) -> Frame:
	return Frame.new(0, _stack(legs), STAND_TOKENS, STAND_LINE)


## Every picture the player can show, for checking them.
static func frames() -> Array[Frame]:
	var out: Array[Frame] = []
	for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
		var table := animation(pose)
		if table != null:
			out.append_array(table.frames)
	return out


## What is wrong with the pictures: a pose with no animation, an animation with
## no pictures, a row that is not the box's width, a character that is not a
## pixel, or a picture that leaves the box. A line starting "warning:" is an
## animation that is set to play but has one picture. Empty when they are right.
## `PlayerBody` reports these in a debug build.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for c in COLOURS:
		if c.length() != 1 or c == EMPTY:
			out.append("COLOURS key '%s' must be one character and not '%s'" % [c, EMPTY])
	for c in BODY_PIXELS + MARK_PIXEL:
		if not COLOURS.has(c):
			out.append("COLOURS needs the body pixels '%s' and the mark '%s', and has no '%s'" % [BODY_PIXELS, MARK_PIXEL, c])
	for pose: PlayerAnimator.Pose in PlayerAnimator.Pose.values():
		var pose_name: String = PlayerAnimator.Pose.keys()[pose]
		var table := animation(pose)
		if table == null:
			out.append("%s has no animation" % pose_name)
			continue
		if table.frames.is_empty():
			out.append("%s has an animation with no pictures" % pose_name)
		elif table.frames.size() == 1 and table.every != 0.0:
			out.append("warning: %s has one picture but plays every %s" % [pose_name, table.every])
		for i in table.frames.size():
			var picture := table.frames[i]
			var name := "%s %d" % [pose_name, i]
			if picture.top < 0 or picture.top + picture.rows.size() > SIZE:
				out.append("%s: rows %d to %d leave the %d-row box" % [name, picture.top, picture.top + picture.rows.size() - 1, SIZE])
			for y in picture.rows.size():
				var row := picture.rows[y]
				if row.length() != SIZE:
					out.append("%s row %d is %d wide, not %d" % [name, y, row.length(), SIZE])
				for c in row:
					if c != EMPTY and not COLOURS.has(c):
						out.append("%s row %d has '%s', which is not %s or one of %s" % [name, y, c, EMPTY, COLOURS.keys()])
	return out


## Picture `index` of `pose` (it wraps), facing `facing`, with the inventory for
## `tokens` carried and `imprint` found cut out of it in `MARK_PIXEL`. The
## picture is cut facing right and mirrored once, afterwards.
static func rects(pose: PlayerAnimator.Pose, index: int, facing: int, tokens: int, imprint: bool) -> Drawn:
	var frames_of := animation(pose).frames
	index = posmod(index, frames_of.size())
	var key := "%d/%d/%d/%d/%s" % [pose, index, signi(facing), tokens, imprint]
	if not _drawn.has(key):
		_drawn[key] = _draw(frames_of[index], facing, tokens, imprint)
	return _drawn[key]


static func _draw(picture: Frame, facing: int, tokens: int, imprint: bool) -> Drawn:
	var rows := picture.rows.duplicate()
	for p in InventoryMarks.pixels(picture, tokens, imprint):
		var y := p.y - picture.top
		if y < 0 or y >= rows.size() or not rows[y][p.x] in BODY_PIXELS:
			continue
		rows[y] = rows[y].substr(0, p.x) + MARK_PIXEL + rows[y].substr(p.x + 1)
	if facing < 0:
		for y in rows.size():
			rows[y] = rows[y].reverse()
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
