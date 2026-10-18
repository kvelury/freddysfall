extends Node2D

const TRANSITION_TIME := 0.5
## How long the shatter plays before the player is put back on safe ground.
const DEATH_TIME := 0.6

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
## Where the player was last standing somewhere safe, and in which room.
var _safe_room := ""
var _safe_position := Vector2.ZERO
## Velocity the player had at a door, given back when the slide ends.
var _carried := Vector2.ZERO


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


## Builds room `id` and puts the player in it, at `world_position` or else at
## the room's start. This is a cut, not a slide, and it is where the player
## comes back to when they die.
func _place_in(id: String, world_position := Vector2.INF) -> void:
	if current != null:
		current.set_exits_active(false)
		current.queue_free()
	current = _make_room(id)
	var at := world_position
	if not at.is_finite():
		at = current.position + current.info.start_position()
	player.place(at, current.world_rects())
	_safe_room = id
	_safe_position = at
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
		var body := player.body_rect()
		if current.touches_hazard(body) or current.is_outside(player.global_position):
			_die()
		else:
			var door := current.touched_door(body)
			if door != null and not door.dest_id.is_empty():
				_on_exit(door)
			elif player.is_on_floor() and current.is_safe_spot(body):
				_safe_room = current.info.id
				_safe_position = player.global_position
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


func _die() -> void:
	_busy = true
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	player.visible = false
	var burst := Shatter.new()
	burst.position = player.global_position
	add_child(burst)
	var timer := create_tween()
	timer.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	timer.tween_interval(DEATH_TIME)
	timer.finished.connect(_respawn)


func _respawn() -> void:
	_place_in(_safe_room, _safe_position)
	player.visible = true
	player.input_enabled = true
	_follow = true
	_busy = false


## Crossing a door keeps the player's place along the wall and their
## velocity. The player is frozen while the camera slides, and gets the
## velocity back when it ends.
func _on_exit(door: Door) -> void:
	if _busy or door.dest_id.is_empty():
		return
	_busy = true
	_follow = false
	_carried = player.velocity
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	current.set_exits_active(false)
	_pending = _make_room(door.dest_id)
	_pending.set_exits_active(false)
	var crossed := Door.crossing(door, _pending.info, player.global_position, _carried)
	_carried = crossed["velocity"]
	player.place(crossed["position"], _pending.world_rects())
	GameState.visit(door.dest_id)
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
	player.velocity = _carried
	player.input_enabled = true
	_busy = false
	_follow = true


func _camera_focus(room: Room, focus: Vector2) -> Vector2:
	return Grid.camera_focus(room.position, room.info.pixel_size, focus)
