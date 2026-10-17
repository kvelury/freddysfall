extends Node2D

const TRANSITION_TIME := 0.5

@onready var rooms_root: Node2D = $Rooms
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D

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
	current = _make_room(WorldData.start_room)
	player.global_position = current.position + Grid.cell_center(current.info.spawn_cell)
	player.reset_physics_interpolation()
	player.velocity = Vector2.ZERO
	camera.position = _camera_focus(current, player.global_position)
	current.set_exits_active(true)
	GameState.visit(WorldData.start_room)


func _physics_process(_delta: float) -> void:
	if not _follow or current == null:
		return
	camera.position = _camera_focus(current, player.global_position)


func _make_room(id: String) -> Room:
	var info = WorldData.get_room(id)
	var room := Room.new()
	room.position = Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	room.build(info)
	room.exit_triggered.connect(_on_exit)
	rooms_root.add_child(room)
	return room


func _on_exit(edge: String, dest_id: String, dest_rect: Rect2i) -> void:
	if _busy or dest_id.is_empty():
		return
	_busy = true
	_follow = false
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	# Physics queries are still flushing inside body_entered. Build the next
	# room on the following frame so new shapes and areas are legal.
	call_deferred("_begin_transition", edge, dest_id, dest_rect)


func _begin_transition(_edge: String, dest_id: String, dest_rect: Rect2i) -> void:
	current.set_exits_active(false)
	_pending = _make_room(dest_id)
	_pending.set_exits_active(false)
	var entry: Vector2i = _pending.info.stand_cell_for_rect(dest_rect)
	player.global_position = _pending.position + Grid.cell_center(entry)
	player.reset_physics_interpolation()
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
