extends TestCase

## Playing with a controller: the stick is digital, the face buttons jump and
## lash, L1 holds the map, Start pauses, and Select / Back opens the dev tools.
## Events go in through the Input singleton as a pad would send them.


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var ok := true
	ok = _actions() and ok
	ok = await _movement() and ok
	ok = await _dev_button() and ok
	finish("CONTROLLER INPUT", ok)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(index: int, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = down
	_send(event)


func _stick(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	_send(event)


func _actions() -> bool:
	var ok := true
	_button(JOY_BUTTON_A, true)
	ok = check(Input.is_action_pressed("jump") and not Input.is_action_pressed("lash"), "the bottom face button jumps") and ok
	_button(JOY_BUTTON_A, false)
	ok = check(not Input.is_action_pressed("jump"), "and lets go") and ok
	_button(JOY_BUTTON_X, true)
	ok = check(Input.is_action_pressed("lash"), "the left face button lashes") and ok
	_button(JOY_BUTTON_X, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	ok = check(Input.is_action_pressed("lash"), "R1 lashes too") and ok
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	_button(JOY_BUTTON_LEFT_SHOULDER, true)
	ok = check(Input.is_action_pressed("map"), "holding L1 is the map") and ok
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	ok = check(not Input.is_action_pressed("map"), "and letting go closes it") and ok
	_stick(0, 0.8)
	ok = check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"), "the left stick moves") and ok
	_stick(0, 0.0)
	# A stick tilted a little up while running is not look-up (that would turn a sideways lash up).
	_stick(0, 1.0)
	_stick(1, -0.6)
	ok = check(not Input.is_action_pressed("look_up"), "a slanted run is not look-up") and ok
	_stick(1, -0.95)
	ok = check(Input.is_action_pressed("look_up"), "a firm push up is") and ok
	_stick(0, 0.0)
	_stick(1, 0.0)
	_button(JOY_BUTTON_DPAD_UP, true)
	ok = check(Input.is_action_pressed("look_up"), "the D-pad looks up") and ok
	_button(JOY_BUTTON_DPAD_UP, false)
	_button(JOY_BUTTON_START, true)
	ok = check(Input.is_action_pressed("pause"), "Start is pause") and ok
	_button(JOY_BUTTON_START, false)
	return ok


## The stick is digital: a half push runs as fast as a key does.
func _movement() -> bool:
	var ok := true
	var world: Node = await boot_world("2", {"scripted": false})
	var player: Player = world.get_node("Player")
	await until(func() -> bool: return not world.is_busy() and player.is_on_floor(), 240)
	await ticks(10)
	_stick(0, 0.55)
	await ticks(45)
	var half := player.velocity.x
	_stick(0, 0.0)
	await ticks(30)
	_stick(0, 1.0)
	await ticks(45)
	var full := player.velocity.x
	_stick(0, 0.0)
	ok = check(absf(half) > 0.0 and is_equal_approx(half, full), "a half push and a full push run at the same speed (%.1f, %.1f)" % [half, full]) and ok
	world.queue_free()
	await process_frame
	return ok


## Select (Back) opens the dev panel and again closes it, in a dev session.
func _dev_button() -> bool:
	var ok := true
	var world: Node = await boot_world("2", {"scripted": false})
	var panel: Node = world.get_node("DevPanel")
	await until(func() -> bool: return not world.is_busy(), 240)
	root.get_node("DevSession").available = true
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	back.pressed = true
	panel._input(back)
	ok = check(panel.opened, "Select opens the dev tools") and ok
	panel._input(back)
	ok = check(not panel.opened, "and closes them") and ok
	root.get_node("DevSession").available = false
	panel._input(back)
	ok = check(not panel.opened, "with no dev session it does nothing") and ok
	world.queue_free()
	await process_frame
	return ok
