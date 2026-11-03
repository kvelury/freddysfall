class_name TongueReach
extends RefCounted

## What the tip of the tongue hits. The running tongue and the solver both ask
## here, so a wall the solver says can be broken is a wall the tongue reaches.
## The tip moves in steps no longer than STEP, and stops at the first thing it
## touches.

## The tip moves in steps no longer than this, so a fast one cannot skip a cell.
const STEP := 4.0
## Half the body's width: the tongue's length is counted from the front.
const FRONT := 5.0
## The mouth's height above the body's centre. A sideways lash starts here.
const MOUTH_RISE := 1.5
## The tip's box going sideways, and going up.
const TIP := Vector2(3.0, 1.0)
const TIP_UP := Vector2(1.0, 3.0)


## Where the tongue leaves the body whose centre is `center`, going along `dir`
## (a unit vector: left, right or up).
static func mouth(center: Vector2, dir: Vector2) -> Vector2:
	if dir.y < 0.0:
		return center + Vector2(0.0, -FRONT)
	return center + Vector2(dir.x * FRONT, -MOUTH_RISE)


## The first thing the tip touches going from `origin` along `dir` for `length`
## pixels, or nothing if the way is clear. `extra` are more rects, in the same
## space as `info` (room pixels): a door block, an Imprint, a moving platform.
## Returns {wall, solid, at, distance}. `wall` is the breakable wall's id, or "".
static func first_hit(info: RoomInfo, origin: Vector2, dir: Vector2, length: float, extra: Array = []) -> Dictionary:
	var size := TIP_UP if absf(dir.y) > absf(dir.x) else TIP
	var steps := maxi(1, ceili(length / STEP))
	var along := 0.0
	for _i in steps:
		along = minf(along + length / float(steps), length)
		var at := origin + dir * along
		var hit := box_hit(info, Rect2(at - size * 0.5, size), extra)
		if bool(hit["solid"]):
			hit["at"] = at
			hit["distance"] = along
			return hit
	return {"wall": "", "solid": false, "at": origin + dir * length, "distance": length}


## What the tip's box is touching. `box` and `extra` are in room pixels.
static func box_hit(info: RoomInfo, box: Rect2, extra: Array = []) -> Dictionary:
	var wall := _wall_touching(info, box)
	if not wall.is_empty():
		return {"wall": wall, "solid": true}
	if _solid_touching(info, box):
		return {"wall": "", "solid": true}
	for rect in extra:
		if (rect as Rect2).intersects(box):
			return {"wall": "", "solid": true}
	return {"wall": "", "solid": false}


static func _wall_touching(info: RoomInfo, box: Rect2) -> String:
	for cell in _cells(box):
		var wall := info.standing_wall_at(cell)
		if not wall.is_empty() and Grid.cell_rect(Rect2i(cell, Vector2i.ONE)).intersects(box):
			return wall
	return ""


static func _solid_touching(info: RoomInfo, box: Rect2) -> bool:
	for cell in _cells(box):
		if cell.x < 0 or cell.y < 0 or cell.x >= info.cell_size.x or cell.y >= info.cell_size.y:
			continue
		if info.is_solid(cell.x, cell.y) and Grid.cell_rect(Rect2i(cell, Vector2i.ONE)).intersects(box):
			return true
	return false


static func _cells(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := float(Grid.CELL)
	var x0 := floori(box.position.x / cell)
	var y0 := floori(box.position.y / cell)
	var x1 := floori((box.end.x - 0.01) / cell)
	var y1 := floori((box.end.y - 0.01) / cell)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out
