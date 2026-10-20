extends CanvasLayer

const VIEW_SIZE := Vector2i(240, 132)
const PANEL_SIZE := Vector2(256, 148)

var _open := false
var _fade := 0.0
var _we_paused := false
var _dim: ColorRect
var _panel: Panel
var _viewport: SubViewport
var _layer: MapLayer
var _marker: Marker
var _legend: Legend
## Whether the zoom changed since the map opened, so closing it saves the game.
var _zoom_changed := false
## What the map is drawn at, and the point of that scaled map at the window's
## centre. The room layer is moved by this, and the marker is placed by it, so
## the two always agree.
var zoom := 1.0
var view_center := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	GameState.room_changed.connect(func(_id: String) -> void: refresh())
	GameState.visited_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	var want := Input.is_action_pressed("map")
	if want != _open:
		_set_open(want)
	if _open:
		if Input.is_action_just_pressed("map_zoom_in"):
			set_level(MapView.step(GameState.map_zoom, 1))
		if Input.is_action_just_pressed("map_zoom_out"):
			set_level(MapView.step(GameState.map_zoom, -1))
	var dest := 1.0 if _open else 0.0
	_fade = move_toward(_fade, dest, delta / 0.1)
	_dim.color = Color(0, 0, 0, 0.72 * _fade)
	_panel.modulate.a = _fade
	_panel.scale = Vector2.ONE * lerpf(0.92, 1.0, _fade)
	var showing := _fade > 0.001
	_dim.visible = showing
	_panel.visible = showing
	if showing:
		_marker.queue_redraw()
	if not _open and _fade == 0.0 and _we_paused:
		get_tree().paused = false
		_we_paused = false


func _set_open(open_map: bool) -> void:
	_open = open_map
	if _open:
		get_tree().paused = true
		_we_paused = true
		refresh()
	elif _zoom_changed:
		# The level is part of the game, so keep it even if the player quits
		# before the next door.
		_zoom_changed = false
		var world := get_parent()
		if world != null and world.has_method("save_now"):
			world.save_now()


## Sets the zoom level (MapView.OUT, MIDDLE or IN), keeps it in the game's
## state, and redraws.
func set_level(level: int) -> void:
	level = MapView.clamp_level(level)
	if level == GameState.map_zoom:
		return
	GameState.map_zoom = level
	_zoom_changed = true
	refresh()


func refresh() -> void:
	var bounds := _visited_bounds()
	var view := Vector2(VIEW_SIZE)
	zoom = MapView.scale_for(GameState.map_zoom, bounds, view)
	var focus := bounds.get_center()
	var info: RoomInfo = WorldData.rooms.get(GameState.current_room_id)
	if info != null and GameState.map_zoom == MapView.MIDDLE:
		focus = MapLayer.room_rect(info).get_center()
	elif info != null and GameState.map_zoom == MapView.IN:
		focus = _player_on_map()
	view_center = MapView.view_center(focus, bounds, zoom, view)
	if _layer != null:
		# The layer is moved itself. A Camera2D here only moves in the physics
		# step, after the one picture this viewport renders for a change, and
		# the map showed the previous step's view.
		_layer.position = view * 0.5 - view_center
		_layer.zoom = zoom
		_layer.queue_redraw()
	if _legend != null:
		_legend.queue_redraw()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Where the player is, in map units (before the zoom).
func _player_on_map() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var info: RoomInfo = WorldData.rooms.get(GameState.current_room_id)
	if info == null:
		return Vector2.ZERO
	if player == null:
		return MapLayer.room_rect(info).get_center()
	var room_origin := Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	return MapLayer.marker_pos(info, player.global_position - room_origin)


func marker_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var info: RoomInfo = WorldData.rooms.get(GameState.current_room_id)
	if player == null or info == null:
		return Vector2(-10, -10)
	return _player_on_map() * zoom - view_center + Vector2(VIEW_SIZE) * 0.5


func _visited_bounds() -> Rect2:
	var bounds := Rect2()
	var first := true
	for room_id in GameState.visited.keys():
		var info: RoomInfo = WorldData.rooms.get(room_id)
		if info == null:
			continue
		var rect := MapLayer.room_rect(info)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if first:
		return Rect2(Vector2.ZERO, MapLayer.ROOM_PX)
	return bounds.grow(4.0)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(0, 0, 0, 0)
	_dim.visible = false
	add_child(_dim)

	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_bottom = PANEL_SIZE.y * 0.5
	_panel.pivot_offset = PANEL_SIZE * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_layer = MapLayer.new()
	_layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_layer)
	add_child(_viewport)

	var texture := TextureRect.new()
	texture.texture = _viewport.get_texture()
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.position = (PANEL_SIZE - Vector2(VIEW_SIZE)) * 0.5
	texture.size = Vector2(VIEW_SIZE)
	texture.focus_mode = Control.FOCUS_NONE
	_panel.add_child(texture)

	_marker = Marker.new()
	_marker.host = self
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.focus_mode = Control.FOCUS_NONE
	_marker.position = texture.position
	_marker.size = Vector2(VIEW_SIZE)
	_panel.add_child(_marker)

	_legend = Legend.new()
	_legend.host = self
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.focus_mode = Control.FOCUS_NONE
	_legend.position = texture.position
	_legend.size = Vector2(VIEW_SIZE)
	_panel.add_child(_legend)


class MapLayer extends Node2D:
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

	func _draw() -> void:
		for room_id in GameState.visited.keys():
			var info: RoomInfo = WorldData.rooms.get(room_id)
			if info == null:
				continue
			var rect := room_rect(info)
			var box := MapView.scaled_rect(rect, zoom)
			if String(room_id) == GameState.current_room_id:
				# Opaque gray. A transparent white fill is premultiplied twice on the
				# web export and disappears into the panel.
				draw_rect(box, Color(0.42, 0.42, 0.42, 1), true)
			_outline(rect, box, info)
			_connectors(rect, box, info)

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
			if dest.is_empty() or not GameState.visited.has(dest):
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


class Marker extends Control:
	var host

	func _draw() -> void:
		if host == null:
			return
		if int(Time.get_ticks_msec() / 250.0) % 2 == 1:
			return
		var pos: Vector2 = host.marker_position()
		draw_rect(Rect2(pos.floor(), Vector2(1, 1)), Color.WHITE)


## The two zoom keys, drawn as symbols in the bottom-right corner.
class Legend extends Control:
	var host

	func _draw() -> void:
		if host == null:
			return
		var pieces := MapView.legend(GameState.map_zoom, Vector2(host.VIEW_SIZE))
		draw_rect(Rect2(pieces["patch"]), Color.BLACK)
		for pixel: Vector2i in pieces["white"]:
			draw_rect(Rect2(Vector2(pixel), Vector2.ONE), Color.WHITE)
		for pixel: Vector2i in pieces["grey"]:
			draw_rect(Rect2(Vector2(pixel), Vector2.ONE), Color(0.42, 0.42, 0.42, 1))
