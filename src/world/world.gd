extends Node2D

const TRANSITION_TIME := 0.5

@onready var rooms_root: Node2D = $Rooms
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D

## Set before the world enters the tree to start in this room. The command
## line (`-- --room=3`) and, on the web, `?room=3` fill it in when it is empty.
var start_override := ""
var current: Room
var _pending: Room
var _busy := false
var _follow := true


func _ready() -> void:
	WorldData.ensure_loaded()
	camera.position_smoothing_enabled = false
	# The camera steps in whole pixels. Interpolating it would blur the
	# integer-scaled tiles while a room scrolls. The player still interpolates.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.make_current()
	var id := start_override if not start_override.is_empty() else _requested_room()
	if id.is_empty():
		id = WorldData.start_room
	elif not WorldData.rooms.has(id):
		push_error("There is no room \"%s\" to start in. Rooms: %s" % [id, ", ".join(WorldData.rooms.keys())])
		id = WorldData.start_room
	_place_in(id)


## Puts the player in a room straight away, with no slide. For testing a room
## without playing to it. Returns false if there is no such room or the world
## is mid-transition.
func warp_to(id: String) -> bool:
	if _busy or not WorldData.rooms.has(id):
		return false
	_place_in(id)
	return true


func _place_in(id: String) -> void:
	if current != null:
		current.set_exits_active(false)
		current.queue_free()
	current = _make_room(id)
	player.place(current.position + Grid.cell_center(current.info.start_cell()), current.world_rects())
	camera.position = _camera_focus(current, player.global_position)
	current.set_exits_active(true)
	GameState.visit(id)


func _requested_room() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			return arg.substr(7)
	if OS.has_feature("web"):
		var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room')")
		if value != null:
			return String(value)
	return ""


func _physics_process(_delta: float) -> void:
	if current == null:
		return
	if not _busy:
		var door := current.touched_door(player.body_rect())
		if door != null and not door.dest_id.is_empty():
			_on_exit(door.edge, door.dest_id, door.dest_rect)
	if not _follow:
		return
	camera.position = _camera_focus(current, player.global_position)


func _make_room(id: String) -> Room:
	var info := WorldData.get_room(id)
	var room := Room.new()
	room.position = Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	room.build(info)
	rooms_root.add_child(room)
	return room


func _on_exit(edge: String, dest_id: String, dest_rect: Rect2i) -> void:
	if _busy or dest_id.is_empty():
		return
	_busy = true
	_follow = false
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	_begin_transition(edge, dest_id, dest_rect)


func _begin_transition(_edge: String, dest_id: String, dest_rect: Rect2i) -> void:
	current.set_exits_active(false)
	_pending = _make_room(dest_id)
	_pending.set_exits_active(false)
	var entry: Vector2i = _pending.info.stand_cell_for_rect(dest_rect)
	player.place(_pending.position + Grid.cell_center(entry), _pending.world_rects())
	GameState.visit(dest_id)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", _camera_focus(_pending, player.global_position), TRANSITION_TIME)
	tween.finished.connect(_finish_transition)


func _finish_transition() -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = _pending
	_pending = null
	if current != null:
		current.set_exits_active(true)
	player.input_enabled = true
	_busy = false
	_follow = true


func _camera_focus(room: Room, focus: Vector2) -> Vector2:
	return Grid.camera_focus(room.position, room.info.pixel_size, focus)
