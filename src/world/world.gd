extends Node2D

const TRANSITION_TIME := 0.5

@onready var rooms_root: Node2D = $Rooms
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D

var current: Room
var _pending: Room
var _busy := false


func _ready() -> void:
	WorldData.ensure_loaded()
	camera.position_smoothing_enabled = false
	camera.make_current()
	current = _make_room(WorldData.start_room)
	player.global_position = current.position + Grid.cell_center(current.info.spawn_cell)
	player.velocity = Vector2.ZERO
	camera.position = _camera_center(current)
	current.set_exits_active(true)
	GameState.visit(WorldData.start_room)


func _make_room(id: String) -> Room:
	var info = WorldData.get_room(id)
	var room := Room.new()
	room.position = Vector2(info.grid_pos) * Grid.ROOM_SIZE
	room.build(info)
	room.exit_triggered.connect(_on_exit)
	rooms_root.add_child(room)
	return room


func _on_exit(edge: String, dest_id: String) -> void:
	if _busy or dest_id.is_empty():
		return
	_busy = true
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	# Physics queries are still flushing inside body_entered. Build the next
	# room on the following frame so new shapes and areas are legal.
	call_deferred("_begin_transition", edge, dest_id)


func _begin_transition(edge: String, dest_id: String) -> void:
	current.set_exits_active(false)
	_pending = _make_room(dest_id)
	_pending.set_exits_active(false)
	var entry: Vector2i = _pending.info.stand_cell_for_entry(_opposite(edge))
	player.global_position = _pending.position + Grid.cell_center(entry)
	GameState.visit(dest_id)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", _camera_center(_pending), TRANSITION_TIME)
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


func _camera_center(room: Room) -> Vector2:
	return room.position + Grid.ROOM_SIZE * 0.5


func _opposite(edge: String) -> String:
	match edge:
		"left":
			return "right"
		"right":
			return "left"
		"up":
			return "down"
		"down":
			return "up"
	return edge
