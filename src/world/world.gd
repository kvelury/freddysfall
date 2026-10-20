extends Node2D

const TRANSITION_TIME := 0.5
## How long the shatter plays before the player is put back on safe ground.
const DEATH_TIME := 0.6
## How long a token takes to fly into a 3TM, the pause after each, and how
## long the spark takes to come back to the player.
const FEED_TIME := 0.45
const FEED_PAUSE := 0.2
const SPARK_TIME := 0.3
## How many stretches of floor are remembered, and how far apart two spots have
## to be, in pixels, to count as different stretches.
const SAFE_HISTORY := 8
const SAFE_SPACING := 30.0

@onready var rooms_root: Node2D = $Rooms
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D
@onready var toast: Toast = $Toast
@onready var imprint: ImprintTool = $Imprint

## Set before the world enters the tree to start in this room. The command
## line (`-- --room=3`) and, on the web, `?room=3` fill it in when it is empty.
## Starting in a chosen room is for testing: it uses no save and writes none.
## `--new-game` (`?new-game=1`) starts over and replaces the save.
var start_override := ""
var current: Room
var _pending: Room
var _busy := false
var _follow := true
## The floor the player has stood on, newest last. Each entry has the "room",
## the "position" they last stood at on that stretch of floor, and the
## "anchor" where the stretch began, so walking along one floor is one entry.
var _safe: Array[Dictionary] = []
## Whether the player has stood on safe floor since they last came back from a
## death. A respawn that dies before that was a bad spot, and goes one back.
var _stood_since_respawn := true
## Velocity the player had at a door, given back when the slide ends.
var _carried := Vector2.ZERO


func _ready() -> void:
	WorldData.ensure_loaded()
	camera.position_smoothing_enabled = false
	# The camera steps in whole pixels. Interpolating it would blur the
	# integer-scaled tiles while a room scrolls. The player still interpolates.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.make_current()
	var id := start_override if not start_override.is_empty() else _launch_arg("room")
	var at := Vector2.INF
	if not id.is_empty():
		Save.enabled = false
		if not WorldData.rooms.has(id):
			push_error("There is no room \"%s\" to start in. Rooms: %s" % [id, ", ".join(WorldData.rooms.keys())])
			id = WorldData.start_room
	else:
		id = WorldData.start_room
		if _launch_arg("new-game").is_empty():
			var saved := Save.load_game()
			if not saved.is_empty():
				id = String(saved["room"])
				at = Vector2(WorldData.get_room(id).grid_pos) * Grid.SCREEN_SIZE + (saved["position"] as Vector2)
	_place_in(id, at)


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
func _place_in(id: String, world_position := Vector2.INF, respawn := false) -> void:
	imprint.clear(false)
	if current != null:
		current.set_exits_active(false)
		current.queue_free()
	current = _make_room(id)
	var at := world_position
	if not at.is_finite():
		at = current.position + current.info.start_position()
	player.place(at, current.world_rects())
	if not respawn:
		_safe.clear()
		_record_safe(id, at)
	camera.position = _camera_focus(current, player.global_position)
	current.set_exits_active(true)
	GameState.visit(id)


## A launch option: `--name=value` or `--name` on the command line, or
## `?name=value` on the web page's address. Empty if it was not given.
func _launch_arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--" + name:
			return "1"
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	if OS.has_feature("web"):
		var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % name)
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
			for thing in current.touched_things(body):
				_collect(thing)
			var door := current.touched_door(body)
			if door != null and not door.dest_id.is_empty():
				_on_exit(door)
			elif player.is_on_floor() and current.is_safe_spot(body):
				_record_safe(current.info.id, player.global_position)
	if not _follow:
		return
	camera.position = _camera_focus(current, player.global_position)


func _make_room(id: String) -> Room:
	var info := WorldData.get_room(id)
	var room := Room.new()
	room.position = Vector2(info.grid_pos) * Grid.SCREEN_SIZE
	room.build(info, GameState.flags, GameState.machines)
	room.exits_opened.connect(_on_exits_opened)
	rooms_root.add_child(room)
	return room


## Whether a door slide or a death is under way and the player is not in control.
func is_busy() -> bool:
	return _busy


func _collect(thing: Node2D) -> void:
	if thing is TokenMachine:
		_feed(thing)
		return
	if thing is Token:
		if not GameState.take_token(thing.def):
			if not thing.noted:
				thing.noted = true
				toast.show_text("You can carry %d tokens" % GameState.TOKEN_CAP)
			return
		thing.collect()
	else:
		toast.show_text(GameState.collect(thing.def))
		thing.collect()
	current.recheck_exits(GameState.flags)
	_autosave(false)


## The player touches a 3TM. With tokens they are fed in one at a time, each
## flying from the player into the next slot; the third makes the machine give
## its upgrade. The player is frozen until it is done.
func _feed(machine: TokenMachine) -> void:
	if machine.spent:
		return
	if GameState.tokens == 0:
		if not machine.noted:
			machine.noted = true
			toast.show_text("%d of %d tokens" % [machine.filled, TokenMachine.COST])
		return
	_busy = true
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	while GameState.tokens > 0 and not machine.spent:
		var slot := machine.filled
		GameState.spend_token()
		var flier := FlyingToken.launch(self, player.global_position, machine.slot_position(slot), FEED_TIME)
		await flier.arrived
		machine.fill()
		GameState.machines[machine.def.id] = machine.filled
		await get_tree().create_timer(FEED_PAUSE, true, true).timeout
	if machine.spent:
		await machine.dispense()
		var spark := FlyingToken.launch(self, machine.mouth_position(), player.global_position, SPARK_TIME, true)
		await spark.arrived
		var burst := Shatter.new()
		burst.position = player.global_position
		add_child(burst)
		toast.show_text(GameState.grant(String(machine.def.props["upgrade"]), String(machine.def.props.get("value", ""))))
		await get_tree().create_timer(FEED_PAUSE, true, true).timeout
	player.input_enabled = true
	_busy = false
	_autosave(false)


## The doors of the room just opened: the blocks no longer collide.
func _on_exits_opened() -> void:
	imprint.sync_solids()


## Writes the save. On entering a room it records where the player is; after
## a pickup it records the last safe floor in this room, so loading never
## puts anyone mid-jump above spikes.
func _autosave(entering: bool) -> void:
	var spot := player.global_position
	if not entering and _safe[-1]["room"] == current.info.id:
		spot = _safe[-1]["position"]
	Save.write(current.info.id, spot - current.position)


## Remembers that the player stood at `at` in room `room_id`.
func _record_safe(room_id: String, at: Vector2) -> void:
	_stood_since_respawn = true
	if not _safe.is_empty():
		var last := _safe[-1]
		if last["room"] == room_id and at.distance_to(last["anchor"]) < SAFE_SPACING:
			last["position"] = at
			return
	_safe.append({"room": room_id, "position": at, "anchor": at})
	if _safe.size() > SAFE_HISTORY:
		_safe.pop_front()


func _die() -> void:
	# Dying again without having stood anywhere since the last respawn means
	# that spot was no good. Go back to the floor before it.
	if not _stood_since_respawn and _safe.size() > 1:
		_safe.pop_back()
	_busy = true
	imprint.clear(true)
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
	var spot := _safe[-1]
	_place_in(spot["room"], spot["position"], true)
	_stood_since_respawn = false
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
	imprint.clear(false)
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
	if current != null:
		_autosave(true)


func _camera_focus(room: Room, focus: Vector2) -> Vector2:
	return Grid.camera_focus(room.position, room.info.pixel_size, focus)
