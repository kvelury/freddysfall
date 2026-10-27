class_name PixelArt
extends RefCounted

## A small picture made of world pixels, written as rows of `#` (on) and `.`
## (off), and drawn as rects. Shapes that were polygons are pictures now, so
## they are the same pixels at every resolution.

static var _cache := {}


## The picture's lit pixels as rects (a run along a row is one rect), with the
## top-left of the first row at `offset`.
static func rects(rows: Array, offset := Vector2i.ZERO) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < row.length():
			if row[x] != "#":
				x += 1
				continue
			var start := x
			while x < row.length() and row[x] == "#":
				x += 1
			out.append(Rect2(Vector2(offset + Vector2i(start, y)), Vector2(x - start, 1)))
	return out


## Draws the picture `name` of PixelShapes with its anchor at `at`.
static func draw(canvas: CanvasItem, name: String, at: Vector2, color := Color.WHITE) -> void:
	if not _cache.has(name):
		var shape: Dictionary = PixelShapes.SHAPES[name]
		_cache[name] = rects(shape["rows"], shape["offset"])
	for box: Rect2 in _cache[name]:
		canvas.draw_rect(Rect2(at + box.position, box.size), color)
