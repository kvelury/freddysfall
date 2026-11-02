class_name LashGeometry
extends RefCounted

## Pure pixel geometry shared by the live lash and solver. Length measures the
## tip centre from the body's front, not from the body's centre or a cell edge.
const FRONT := 5.0
const MOUTH_RISE := 1.5
const TIP := Vector2(3.0, 1.0)
const TIP_UP := Vector2(1.0, 3.0)


static func direction(facing: int, up: bool) -> Vector2:
	return Vector2.UP if up else Vector2(float(facing), 0.0)


static func origin(body: Vector2, facing: int, up: bool) -> Vector2:
	return body + (Vector2(0.0, -FRONT) if up else Vector2(float(facing) * FRONT, -MOUTH_RISE))


static func tip(body: Vector2, facing: int, up: bool, extension: float) -> Vector2:
	return origin(body, facing, up) + direction(facing, up) * extension


static func tip_box(at: Vector2, up: bool) -> Rect2:
	var size := TIP_UP if up else TIP
	return Rect2(at - size * 0.5, size)


## First extension at which the tip touches a solid's edge. Contact alone is
## not overlap (Rect2.intersects is strict); a lash must extend past this value.
## A box already overlapping at the origin is hit even at zero length.
static func contact(body: Vector2, facing: int, up: bool, solid: Rect2) -> float:
	var box := tip_box(origin(body, facing, up), up)
	if box.intersects(solid):
		return 0.0
	if up:
		if box.position.x >= solid.end.x or box.end.x <= solid.position.x or solid.position.y >= box.end.y:
			return INF
		return maxf(0.0, box.position.y - solid.end.y)
	if box.position.y >= solid.end.y or box.end.y <= solid.position.y:
		return INF
	if facing > 0:
		return maxf(0.0, solid.position.x - box.end.x) if solid.end.x > box.position.x else INF
	return maxf(0.0, box.position.x - solid.end.x) if solid.position.x < box.end.x else INF


## Index of the nearest solid actually overlapped within length, or -1. Stable
## input order breaks ties.
static func first_solid(body: Vector2, facing: int, up: bool, length: float, solids: Array) -> int:
	var nearest := INF
	var found := -1
	for i in solids.size():
		var rect: Rect2 = solids[i]
		var distance := contact(body, facing, up, rect)
		if distance < nearest and (distance < length or tip_box(origin(body, facing, up), up).intersects(rect)):
			nearest = distance
			found = i
	return found
