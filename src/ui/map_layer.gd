class_name MapLayer
extends Node2D

## The rooms of the map, drawn as outlines with doors for gaps. The Tab map
## draws the visited ones; the dev map draws all of them, labelled, with one
## selected. The defaults give the Tab map.

const ROOM_PX := Vector2(32, 18)
const STRIDE := Vector2(40, 26)

static func map_size(info: RoomInfo) -> Vector2:
	# A multi-screen room is one continuous rectangle. The stride gap
	# stays outside the room, between it and its neighbors.
	return Vector2(info.screens) * STRIDE - (STRIDE - ROOM_PX)

static func room_rect(info: RoomInfo) -> Rect2:
	return Rect2(Vector2(info.grid_pos) * STRIDE, map_size(info))

static func marker_pos(info: RoomInfo, local_px: Vector2) -> Vector2:
	var cells := local_px / float(Grid.CELL)
	var sx := clampi(int(cells.x / float(Grid.SCREEN_CELLS.x)), 0, info.screens.x - 1)
	var sy := clampi(int(cells.y / float(Grid.SCREEN_CELLS.y)), 0, info.screens.y - 1)
	var lx := cells.x - float(sx * Grid.SCREEN_CELLS.x)
	var ly := cells.y - float(sy * Grid.SCREEN_CELLS.y)
	return Vector2(info.grid_pos) * STRIDE + Vector2(sx, sy) * STRIDE + Vector2(lx, ly)

## What the map is drawn at. Every corner is scaled and rounded to a pixel,
## and lines stay one pixel thick, so the map is as sharp at every level.
var zoom := 1.0

## The rooms to draw, as a Callable returning room ids. Unset, the visited ones.
var rooms := Callable()
## Whether a door is drawn to every room it leads to, not only visited ones.
var connect_all := false
## The room filled grey. Empty is the room the player is in.
var current_id := ""
## A room outlined inside, by the dev map. Empty is none.
var selected_id := ""
## Whether each room's id is written in it.
var labels := false


## The ids of the rooms drawn.
func room_ids() -> Array:
	if rooms.is_valid():
		return rooms.call()
	return GameState.visited.keys()


## The id of the room under `point` (map units), or "" for none. `ids` are the
## rooms looked through; a gap between rooms is no room.
static func room_at(ids: Array, point: Vector2) -> String:
	for room_id in ids:
		var info: RoomInfo = WorldData.rooms.get(room_id)
		if info != null and room_rect(info).has_point(point):
			return String(room_id)
	return ""


func _draw() -> void:
	var here := current_id if not current_id.is_empty() else GameState.current_room_id
	for room_id in room_ids():
		var info: RoomInfo = WorldData.rooms.get(room_id)
		if info == null:
			continue
		var rect := room_rect(info)
		var box := MapView.scaled_rect(rect, zoom)
		if String(room_id) == here:
			# Opaque gray. A transparent white fill is premultiplied twice on the
			# web export and disappears into the panel.
			draw_rect(box, Color(0.42, 0.42, 0.42, 1), true)
		_outline(rect, box, info)
		_connectors(rect, box, info)
		if String(room_id) == selected_id:
			draw_rect(box.grow(-2.0), Color.WHITE, false)
		if labels:
			_label(String(room_id), box)


## The id, centred in `box`, white on a black edge so it reads on the grey fill.
func _label(text: String, box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var size := 6
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := box.get_center() + Vector2(-width * 0.5, font.get_ascent(size) * 0.5)
	draw_string_outline(font, at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color.BLACK)
	draw_string(font, at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _px(units: float) -> float:
	return roundf(units * zoom)

func _outline(rect: Rect2, box: Rect2, info: RoomInfo) -> void:
	_horizontal(rect.position.x, box.position.y, rect.size.x, _gaps(info, "up"))
	_horizontal(rect.position.x, box.end.y - 1.0, rect.size.x, _gaps(info, "down"))
	_vertical(rect.position.y, box.position.x, rect.size.y, _gaps(info, "left"))
	_vertical(rect.position.y, box.end.x - 1.0, rect.size.y, _gaps(info, "right"))

func _connectors(rect: Rect2, box: Rect2, info: RoomInfo) -> void:
	for ex in info.exits:
		var edge := ex.edge
		var dest := ex.dest_id
		if dest.is_empty() or not (connect_all or GameState.visited.has(dest)):
			continue
		var span := _edge_span(ex.rect, edge)
		var gap := STRIDE - ROOM_PX
		var mid := (span.x + span.y) * 0.5
		match edge:
			"right":
				var y := _px(rect.position.y + mid)
				draw_rect(Rect2(box.end.x, y, _px(rect.end.x + gap.x) - box.end.x, 1), Color.WHITE)
			"left":
				var y := _px(rect.position.y + mid)
				var x := _px(rect.position.x - gap.x)
				draw_rect(Rect2(x, y, box.position.x - x, 1), Color.WHITE)
			"down":
				var x := _px(rect.position.x + mid)
				draw_rect(Rect2(x, box.end.y, 1, _px(rect.end.y + gap.y) - box.end.y), Color.WHITE)
			"up":
				var x := _px(rect.position.x + mid)
				var y := _px(rect.position.y - gap.y)
				draw_rect(Rect2(x, y, 1, box.position.y - y), Color.WHITE)

func _gaps(info: RoomInfo, edge: String) -> Array:
	var gaps: Array = []
	for ex in info.exits:
		if ex.edge != edge:
			continue
		gaps.append(_edge_span(ex.rect, edge))
	return gaps

func _edge_span(rect: Rect2i, edge: String) -> Vector2:
	var screen := Grid.SCREEN_CELLS
	if edge == "left" or edge == "right":
		var sy := int(rect.position.y / screen.y)
		var y0 := rect.position.y % screen.y
		return Vector2(sy * STRIDE.y + y0, sy * STRIDE.y + y0 + rect.size.y)
	var sx := int(rect.position.x / screen.x)
	var x0 := rect.position.x % screen.x
	return Vector2(sx * STRIDE.x + x0, sx * STRIDE.x + x0 + rect.size.x)

## A side drawn along x, from `x0` (map units) for `length`, at the pixel
## row `y`, with a gap for each door (in map units from `x0`).
func _horizontal(x0: float, y: float, length: float, gaps: Array) -> void:
	var cursor := 0.0
	var sorted: Array = gaps.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for gap in sorted:
		var g0: float = gap.x
		var g1: float = gap.y
		if g0 > cursor:
			draw_rect(Rect2(_px(x0 + cursor), y, _px(x0 + g0) - _px(x0 + cursor), 1), Color.WHITE)
		cursor = maxf(cursor, g1)
	if cursor < length:
		draw_rect(Rect2(_px(x0 + cursor), y, _px(x0 + length) - _px(x0 + cursor), 1), Color.WHITE)

## The same, down the side at the pixel column `x`.
func _vertical(y0: float, x: float, length: float, gaps: Array) -> void:
	var cursor := 0.0
	var sorted: Array = gaps.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for gap in sorted:
		var g0: float = gap.x
		var g1: float = gap.y
		if g0 > cursor:
			draw_rect(Rect2(x, _px(y0 + cursor), 1, _px(y0 + g0) - _px(y0 + cursor)), Color.WHITE)
		cursor = maxf(cursor, g1)
	if cursor < length:
		draw_rect(Rect2(x, _px(y0 + cursor), 1, _px(y0 + length) - _px(y0 + cursor)), Color.WHITE)
