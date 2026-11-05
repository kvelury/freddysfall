class_name KeyCap
extends Control

## One key drawn as a small black box with a white border, in UI units. The
## arrow keys and the left mouse button are drawn as little pixel pictures.
## The pictures are here and not in PixelShapes, which is the polygon baseline
## that `tools/pixel_check.sh --shapes` works from.

const HEIGHT := 11
const FONT_SIZE := 8
const ARROWS := {
	"Up": ["..#..", ".###.", "#####"],
	"Down": ["#####", ".###.", "..#.."],
	"Left": ["..#", ".##", "###", ".##", "..#"],
	"Right": ["#..", "##.", "###", "##.", "#.."],
}
## A PlayStation pad's face buttons.
const FACES := {
	"Cross": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"Circle": [".###.", "#...#", "#...#", "#...#", ".###."],
	"Square": ["#####", "#...#", "#...#", "#...#", "#####"],
	"Triangle": ["..#..", ".#.#.", ".#.#.", "#...#", "#####"],
}
const MOUSE := [
	".#####.",
	"####..#",
	"####..#",
	"####..#",
	"#######",
	"#.....#",
	"#.....#",
	"#.....#",
	".#####.",
]

var key := ""
## Drawn inverted (white, with black ink): the slot being edited in Settings.
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var _picture: Array = []


func _init(text := "") -> void:
	key = text
	if ARROWS.has(text):
		_picture = ARROWS[text]
	elif FACES.has(text):
		_picture = FACES[text]
	elif text == "MouseLeft":
		_picture = MOUSE
	var width := float(HEIGHT)
	if _picture.is_empty():
		width = maxf(width, UiTheme.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 6.0)
	custom_minimum_size = Vector2(width, HEIGHT)


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var ink := Color.BLACK if selected else Color.WHITE
	draw_rect(box, Color.WHITE if selected else Color.BLACK)
	draw_rect(box, Color.WHITE, false)
	if _picture.is_empty():
		var font := UiTheme.FONT
		var text_size := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var at := Vector2((size.x - text_size.x) / 2.0, (size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0)
		draw_string(font, at.round(), key, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink)
		return
	var width: int = (_picture[0] as String).length()
	var offset := Vector2i((int(size.x) - width) / 2, (HEIGHT - _picture.size()) / 2)
	for rect in PixelArt.rects(_picture, offset):
		draw_rect(rect, ink)
