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
	var world := get_parent()
	var allowed: bool = world.modal_owner.is_empty() or world.modal_owner == "map"
	var want := allowed and Input.is_action_pressed("map")
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
		get_parent().release_modal("map")
		_we_paused = false


func _set_open(open_map: bool) -> void:
	_open = open_map
	if _open:
		_we_paused = get_parent().acquire_modal("map")
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
