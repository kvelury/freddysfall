extends Node2D

const TRANSITION_TIME := 0.5
const SUCK_TIME := 0.3

@onready var rooms_root: Node2D = $Rooms
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D

var current: Room
var _pending: Room
var _busy := false
var _follow := true
var _landing_pos := Vector2.ZERO
var _hover_pos := Vector2.ZERO
var _drop_after_camera := false
var _release_when_settled := false
var _settle_wait := 0


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
	if _follow and current != null:
		camera.position = _camera_focus(current, player.global_position)
	if not _release_when_settled:
		return
	_settle_wait += 1
	if player.settling and _settle_wait < 120:
		return
	if player.settling:
		player.global_position = _landing_pos
		player.velocity = Vector2.ZERO
		player.settling = false
		player.reset_physics_interpolation()
	_release_player()


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
	_drop_after_camera = false
	_release_when_settled = false
	player.input_enabled = false
	player.settling = false
	player.velocity = Vector2.ZERO
	# Physics queries are still flushing inside body_entered. Build the next
	# room on the following frame so new shapes and areas are legal.
	call_deferred("_begin_transition", edge, dest_id, dest_rect)


func _begin_transition(edge: String, dest_id: String, dest_rect: Rect2i) -> void:
	current.set_exits_active(false)
	_pending = _make_room(dest_id)
	_pending.set_exits_active(false)
	_prepare_landing(dest_rect)
	GameState.visit(dest_id)
	var vertical := edge == "up" or edge == "down"
	if vertical:
		player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var suck := _suck_target(current, _matching_exit(current, edge, dest_id, dest_rect))
		var tween := create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(player, "global_position", suck, SUCK_TIME)
		tween.finished.connect(_suck_finished)
	else:
		player.global_position = _landing_pos
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		_slide_camera(false)


func _prepare_landing(dest_rect: Rect2i) -> void:
	var info = _pending.info
	var landing: Dictionary = info.vertical_landing(dest_rect)
	if landing.is_empty():
		var cell: Vector2i = info.stand_cell_for_rect(dest_rect)
		_landing_pos = _pending.position + Grid.cell_center(cell)
		_hover_pos = _landing_pos
		return
	var cell: Vector2i = landing["cell"]
	_landing_pos = _pending.position + info.plant_position(cell)
	_hover_pos = _landing_pos + Vector2(0.0, -info.drop_lift(cell))


func _suck_finished() -> void:
	player.global_position = _hover_pos
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	_slide_camera(true)


func _slide_camera(then_drop: bool) -> void:
	_drop_after_camera = then_drop
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	var focus := _landing_pos if then_drop else player.global_position
	tween.tween_property(camera, "position", _camera_focus(_pending, focus), TRANSITION_TIME)
	tween.finished.connect(_finish_transition)


func _finish_transition() -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = _pending
	_pending = null
	if _drop_after_camera:
		_drop_after_camera = false
		player.settling = true
		player.velocity = Vector2.ZERO
		_settle_wait = 0
		_release_when_settled = true
		return
	_release_player()


func _release_player() -> void:
	_release_when_settled = false
	player.settling = false
	player.exit_lock = 0.2
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	player.reset_physics_interpolation()
	if current != null:
		current.set_exits_active(true)
	player.input_enabled = true
	_busy = false
	_follow = true


func _matching_exit(room: Room, edge: String, dest_id: String, dest_rect: Rect2i) -> Dictionary:
	if room == null:
		return {}
	for ex in room.info.exits:
		if String(ex["edge"]) == edge and String(ex["dest_id"]) == dest_id and ex["dest_rect"] == dest_rect:
			return ex
	return {}


func _suck_target(room: Room, ex: Dictionary) -> Vector2:
	if ex.is_empty():
		return player.global_position
	var rect: Rect2i = ex["rect"]
	var pixel := Grid.cell_rect(rect)
	var center := room.position + pixel.get_center()
	match String(ex["edge"]):
		"up":
			return Vector2(center.x, room.position.y + pixel.position.y + 5.0)
		"down":
			return Vector2(center.x, room.position.y + pixel.end.y - 5.0)
	return center


func _camera_focus(room: Room, focus: Vector2) -> Vector2:
	return Grid.camera_focus(room.position, room.info.pixel_size, focus)
