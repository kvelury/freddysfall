class_name MapView
extends RefCounted

## How the map window is zoomed, and what its legend looks like. Pure
## functions of numbers, with no autoloads, so the tests ask them directly.
##
## The map has three levels. Out always shows every visited room, however big
## the map gets, and never zooms in past Middle. Middle is the view the map
## always had. In is twice that, on the player.

const OUT := 0
const MIDDLE := 1
const IN := 2
const IN_SCALE := 2.0

## The white or grey pixels of the legend are on this black patch, with a
## pixel of black round them, a pixel from the corner of the view.
const LEGEND_MARGIN := 1
const LEGEND_PAD := 2
const ROW_GAP := 2
const GLYPH_GAP := 2

const ARROW_UP: Array[String] = [
	"..#..",
	".###.",
	"#.#.#",
	"..#..",
	"..#..",
]
const ARROW_DOWN: Array[String] = [
	"..#..",
	"..#..",
	"#.#.#",
	".###.",
	"..#..",
]
## A magnifying glass: the ring and handle. The plus or minus is drawn in it.
const GLASS: Array[String] = [
	".###...",
	"#...#..",
	"#...#..",
	"#...#..",
	".###...",
	".....#.",
	"......#",
]
const PLUS: Array[String] = [
	".#.",
	"###",
	".#.",
]
const MINUS: Array[String] = [
	"...",
	"###",
	"...",
]


static func clamp_level(level: int) -> int:
	return clampi(level, OUT, IN)


## One press of zoom in (+1) or zoom out (-1). It stops at the ends.
static func step(level: int, direction: int) -> int:
	return clamp_level(level + direction)


## How much the map is drawn at, for a map taking up `bounds` in a window of
## `view` pixels.
static func scale_for(level: int, bounds: Rect2, view: Vector2) -> float:
	match clamp_level(level):
		OUT:
			var fit := minf(view.x / maxf(bounds.size.x, 1.0), view.y / maxf(bounds.size.y, 1.0))
			return minf(1.0, fit)
		IN:
			return IN_SCALE
	return 1.0


## `rect` drawn at `scale`: each corner scaled and then rounded to a pixel, so
## two rooms that touch still touch and ones that do not still do not.
static func scaled_rect(rect: Rect2, scale: float) -> Rect2:
	var a := (rect.position * scale).round()
	var b := (rect.end * scale).round()
	return Rect2(a, b - a)


## Where the window's centre is, in the scaled map, to look at `focus` (in map
## units). It does not look past the edge of the visited map when the map
## fills the window, and is a whole pixel so the lines stay sharp.
static func camera_for(focus: Vector2, bounds: Rect2, scale: float, view: Vector2) -> Vector2:
	var center := focus * scale
	var low := bounds.position * scale + view * 0.5
	var high := bounds.end * scale - view * 0.5
	if bounds.size.x * scale > view.x:
		center.x = clampf(center.x, low.x, high.x)
	if bounds.size.y * scale > view.y:
		center.y = clampf(center.y, low.y, high.y)
	return center.round()


## The legend, in window pixels: a patch to blacken, and the pixels of the
## zoom in row (an up arrow and a magnifying glass with a plus) over the zoom
## out row (a down arrow and one with a minus). A row that can do nothing more,
## because the map is at that end, is grey.
static func legend(level: int, view: Vector2) -> Dictionary:
	var level_now := clamp_level(level)
	var row_height := GLASS.size()
	var row_width := ARROW_UP[0].length() + GLYPH_GAP + GLASS[0].length()
	var size := Vector2i(row_width + 2 * LEGEND_PAD, 2 * row_height + ROW_GAP + 2 * LEGEND_PAD)
	var patch := Rect2i(Vector2i(view) - size - Vector2i(LEGEND_MARGIN, LEGEND_MARGIN), size)
	var white: Array[Vector2i] = []
	var grey: Array[Vector2i] = []
	var rows := [
		{"arrow": ARROW_UP, "sign": PLUS, "spent": level_now == IN},
		{"arrow": ARROW_DOWN, "sign": MINUS, "spent": level_now == OUT},
	]
	for i in rows.size():
		var row: Dictionary = rows[i]
		var into: Array[Vector2i] = grey if row["spent"] else white
		var top := patch.position + Vector2i(LEGEND_PAD, LEGEND_PAD + i * (row_height + ROW_GAP))
		var arrow: Array[String] = row["arrow"]
		_stamp(into, arrow, top + Vector2i(0, (row_height - arrow.size()) / 2))
		var glass_at := top + Vector2i(arrow[0].length() + GLYPH_GAP, 0)
		_stamp(into, GLASS, glass_at)
		_stamp(into, row["sign"], glass_at + Vector2i(1, 1))
	return {"patch": patch, "white": white, "grey": grey}


static func _stamp(into: Array[Vector2i], rows: Array[String], at: Vector2i) -> void:
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				into.append(at + Vector2i(x, y))
