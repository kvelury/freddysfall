class_name DevMap
extends Control

## The dev panel's map: every room in the world, not only the visited ones, each
## labelled with its id, drawn like the Tab map. Click one to pick it, and
## double-click to start a test in it. The room being edited is outlined inside.

signal picked(id: String)
signal activated(id: String)

## The most the map is drawn at. Every corner is rounded to a pixel by
## MapView.scaled_rect, so the lines are as sharp as on the Tab map at any scale.
const MAX_ZOOM := 2.0

var _layer: MapLayer
var _marker: Marker


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layer = MapLayer.new()
	_layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_layer.rooms = func() -> Array: return WorldData.rooms.keys()
	_layer.connect_all = true
	_layer.labels = true
	add_child(_layer)
	_marker = Marker.new()
	_marker.host = self
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_marker)
	resized.connect(fit)
	fit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, false)


## Every room's rectangle together, with a margin, in map units.
func bounds() -> Rect2:
	var out := Rect2()
	var first := true
	for info: RoomInfo in WorldData.rooms.values():
		var rect := MapLayer.room_rect(info)
		out = rect if first else out.merge(rect)
		first = false
	if first:
		return Rect2(Vector2.ZERO, MapLayer.ROOM_PX)
	return out.grow(4.0)


## Scales and places the map so all of it shows in the control.
func fit() -> void:
	if _layer == null:
		return
	var whole := bounds()
	var room := minf(size.x / maxf(whole.size.x, 1.0), size.y / maxf(whole.size.y, 1.0))
	_layer.zoom = clampf(room, 0.1, MAX_ZOOM)
	var centre := MapView.view_center(whole.get_center(), whole, _layer.zoom, size)
	_layer.position = size * 0.5 - centre
	_layer.queue_redraw()
	queue_redraw()


## Outlines `id` inside, or none for an id that is not a room.
func select(id: String) -> void:
	if _layer == null:
		return
	_layer.selected_id = id if WorldData.rooms.has(id) else ""
	_layer.current_id = GameState.current_room_id
	_layer.queue_redraw()


func selected() -> String:
	return "" if _layer == null else _layer.selected_id


## The room at `point` (in this control's pixels), or "".
func room_at(point: Vector2) -> String:
	return MapLayer.room_at(WorldData.rooms.keys(), (point - _layer.position) / _layer.zoom)


## Where room `id` is centred, in this control's pixels. For tests and focus.
func room_center(id: String) -> Vector2:
	var info: RoomInfo = WorldData.rooms.get(id)
	if info == null:
		return Vector2(-1, -1)
	return MapLayer.room_rect(info).get_center() * _layer.zoom + _layer.position


## Where the player is, in this control's pixels.
func marker_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var info: RoomInfo = WorldData.rooms.get(GameState.current_room_id)
	if player == null or info == null:
		return Vector2(-10, -10)
	var origin := Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	return MapLayer.marker_pos(info, player.global_position - origin) * _layer.zoom + _layer.position


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var id := room_at(event.position)
	if id.is_empty():
		return
	picked.emit(id)
	if event.double_click:
		activated.emit(id)
	accept_event()


## The player, a blinking pixel, as on the Tab map.
class Marker extends Control:
	var host

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if host == null or int(Time.get_ticks_msec() / 250.0) % 2 == 1:
			return
		draw_rect(Rect2(host.marker_position().floor(), Vector2.ONE), Color.WHITE)
