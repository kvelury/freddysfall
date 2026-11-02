extends SceneTree

## Real SceneTree callbacks: no test invokes a gameplay physics method.
const DT := 1.0 / 60.0
var _ok := true
var _world: Node
var _samples: Array[Dictionary] = []
var _deltas: Array[float] = []

class SessionWorld extends Node:
	func is_busy() -> bool:
		return false

class Observer extends Node:
	var observe: Callable
	func _physics_process(delta: float) -> void:
		observe.call(delta)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_ok = false
		print("FAIL ", message)

func _run() -> void:
	var normal: Array[Dictionary] = await _simulate(false)
	var slow: Array[Dictionary] = await _simulate(true)
	_check(normal == slow, "equal callback counts give identical player/mover/tongue/lifetime states at normal and quarter speed")
	var session := root.get_node("DevSession")
	session.reset_to_normal()
	var stub := SessionWorld.new()
	session.mode = session.Mode.DEV_TEST
	Engine.time_scale = 0.8
	Engine.physics_ticks_per_second = 48
	session.set_slow_motion(stub, true)
	session.set_slow_motion(stub, true)
	_check(Engine.physics_ticks_per_second == 12 and is_equal_approx(Engine.time_scale, 0.2), "repeated enable preserves the original baseline")
	session.configure(false, false)
	_check(Engine.physics_ticks_per_second == 48 and is_equal_approx(Engine.time_scale, 0.8), "fresh configure restores the captured baseline")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	stub.free()
	_check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "menu reset restores both clock settings")
	print("PHYSICS ORDER %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)

func _simulate(slow: bool) -> Array[Dictionary]:
	var state := root.get_node("GameState")
	var session := root.get_node("DevSession")
	state.reset()
	_world = load("res://src/world/world.tscn").instantiate()
	_world.start_override = "7"
	root.add_child(_world)
	session.mode = session.Mode.DEV_TEST
	_world.player.scripted = true
	_world.tongue.scripted = true
	state.abilities.tongue_unlocked = true
	var room: Room = _world.current
	# A high, safe fall gives movement on every callback, away from authored
	# hazards and doors. A second live room models the transition overlap.
	_world.player.place(room.position + Vector2(75, 100), room.world_rects())
	_world.player.scripted_x = 1.0
	var second: Room = _world._make_room("12")
	second.set_exits_active(false)
	var expiring := ImprintPlatform.new(Rect2(50, 120, 10, 10), DT * 0.5)
	_world.imprint.platforms.append(expiring)
	var lasting := ImprintPlatform.new(Rect2(200, 120, 30, 10), 1.0)
	_world.imprint.platforms.append(lasting)
	_world.imprint.sync_solids()
	_world.tongue.scripted_lash = true
	var after_player := Observer.new()
	after_player.process_physics_priority = -15
	after_player.observe = func(_delta: float) -> void:
		if room.tick == 1:
			_check(_world.player.global_position != room.position + Vector2(75, 100), "player steps before tongue processing")
			_check(not _world.tongue.active, "tongue has not processed the first lash before player movement")
	_world.add_child(after_player)
	var after_tongue := Observer.new()
	after_tongue.process_physics_priority = -5
	after_tongue.observe = func(_delta: float) -> void:
		if room.tick == 1:
			_check(_world.tongue.active, "tongue processes the first lash before world interactions")
	_world.add_child(after_tongue)
	_check(_world.process_physics_priority == 0, "world interactions follow tongue hits")
	var before_player := Observer.new()
	before_player.process_physics_priority = -25
	var observations := [0]
	before_player.observe = func(_delta: float) -> void:
		if observations[0] == 0:
			_check(room.tick == 1 and second.tick == 1, "both rooms advance before the first player callback")
			_check(not _world.imprint.platforms.has(expiring), "expired Imprint footing is removed before the first player callback")
			_check(_world.player.global_position == room.position + Vector2(75, 100), "player has not stepped before footing expiry")
		observations[0] += 1
	_world.add_child(before_player)
	var after := Observer.new()
	after.process_physics_priority = 100
	_samples = []
	_deltas = []
	after.observe = func(delta: float) -> void:
		_deltas.append(delta)
		_samples.append({"tick": room.tick, "second": second.tick, "position": _world.player.global_position, "velocity": _world.player.velocity, "extension": _world.tongue.extension, "phase": _world.tongue.phase, "time": _world.tongue._time, "age": lasting.age, "footing": lasting.drawn_rect(), "cooldown": _world.imprint.cooldown_left})
	_world.add_child(after)
	if slow:
		_check(session.set_slow_motion(_world, true).is_empty(), "quarter speed enabled")
	# Modal pause freezes callbacks and preserves clock ownership.
	_check(_world.acquire_modal("physics-test"), "pause acquired")
	await process_frame
	await process_frame
	_check(_samples.is_empty(), "paused tree runs no gameplay callbacks")
	_world.release_modal("other-owner")
	_check(paused, "another owner cannot resume gameplay")
	_world.release_modal("physics-test")
	while _samples.size() < 12:
		await physics_frame
	# physics_frame is emitted before callbacks; stop on the next idle frame.
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_check(_world.tongue.extension > 0.0, "tongue advanced through real callbacks")
	for delta in _deltas:
		_check(absf(delta - DT) < 0.000001, "engine callback delta remains 1/60 game seconds: %s" % delta)
	var result: Array[Dictionary] = _samples.slice(0, 12)
	session._normal_speed()
	_check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0, "clock restores after slow simulation")
	_world.free()
	await process_frame
	return result
