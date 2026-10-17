class_name ExitHalo
extends Node2D

const SIZE := 64
const FRAMES := 12

var direction := Vector2.LEFT
var _sprite: Sprite2D
var _frames: Array[ImageTexture] = []
var _frame := -1


func _ready() -> void:
	for i in FRAMES:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_paint(image, i)
		_frames.append(ImageTexture.create_from_image(image))
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = _frames[0]
	add_child(_sprite)


func _process(_delta: float) -> void:
	if _frames.is_empty():
		return
	var frame := int(Time.get_ticks_msec() / 90) % _frames.size()
	if frame == _frame:
		return
	_frame = frame
	_sprite.texture = _frames[frame]


func _paint(image: Image, frame: int) -> void:
	var pulse := 20.0 + 6.0 * (0.5 + 0.5 * sin(TAU * float(frame) / float(FRAMES)))
	var center := SIZE / 2
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x - center, y - center)
			if point.dot(direction) < -0.5:
				continue
			var dist := point.length()
			if dist > pulse:
				continue
			var intensity := (1.0 - dist / pulse) * 0.55
			var on_ring := absf(dist - pulse * 0.62) < 0.85 or absf(dist - pulse * 0.9) < 0.7
			var threshold := float(_BAYER[y % 4][x % 4]) / 16.0
			if on_ring or intensity > threshold or _twinkle(x, y, frame):
				image.set_pixel(x, y, Color.WHITE)


func _twinkle(x: int, y: int, frame: int) -> bool:
	var h := (x * 17 + y * 31) % 29
	if h > 1:
		return false
	return (frame + x + y) % 4 == 0


const _BAYER := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]
