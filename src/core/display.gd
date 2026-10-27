class_name Display
extends RefCounted

## The picture is drawn at `RENDER_SCALE` screen pixels to a world pixel. The
## world is still 320 x 180 world pixels a screen (`Grid.SCREEN_SIZE`), the camera
## zooms, and the viewport is `VIEWPORT`. Text and other UI are drawn finer; the
## world is not: everything in it lands on whole world pixels (the world-pixel
## grid), so it looks as it did at 320 x 180. See "Frame and scale" in the design doc.

const RENDER_SCALE := 2
const VIEWPORT := Vector2i(640, 360)
## Nodes in this group are meant to be drawn finer than a world pixel, so the
## pixel check leaves them out. Nothing is in it yet.
const FINE_GROUP := "fine_pixels"


## The whole world pixel a coordinate falls on. A screen pixel is lit when its
## centre is inside a shape and an edge belongs to the pixel after it, so a
## shape at 320 x 180 took the pixels this gives: x.5 goes down to x.
static func snapf(value: float) -> float:
	return ceilf(value - 0.5)


static func snap(point: Vector2) -> Vector2:
	return Vector2(snapf(point.x), snapf(point.y))


## The rect that is lit when `box` is drawn at 320 x 180: both corners snapped.
static func snap_rect(box: Rect2) -> Rect2:
	var from := snap(box.position)
	return Rect2(from, snap(box.end) - from)
