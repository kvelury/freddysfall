extends SceneTree

## The health and token HUD. Its layout, how it follows GameState, a pickup
## flying in before it counts, a death emptying a pip, a save room filling the
## bar again, and a sync showing the state at once with nothing animating.

const TEMP := "user://hud_test.json"

var ok := true


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var state: Node = root.get_node("GameState")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = false
	state.reset()

	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "2"
	root.add_child(world)
	await process_frame
	var hud: Node = world.get_node("Hud")
	_layout(hud)

	_check(hud.layer == 9 and hud.scale == Vector2.ONE * float(Display.RENDER_SCALE), "the HUD is a UI layer under the map, drawn at the render scale")
	_check(hud.shown_tokens == 0 and hud.shown_max == 0 and not hud.busy(), "a new game shows an empty heart and no bar")
	_check(hud.to_ui(world.camera.position) == Vector2(160, 90), "the camera's centre is the middle of the UI (%s)" % hud.to_ui(world.camera.position))

	# A token flies in, and only counts when it lands.
	var token: Node2D = _things(world.current, "Token")[0]
	var from: Vector2 = hud.to_ui(token.global_position)
	var token_def: EntityDef = token.def
	var token_at := token.position
	world._collect(token)
	_check(state.tokens == 1 and hud.flights.size() == 1, "taking a token starts one flight")
	_check(hud.flights[0]["from"] == from and hud.flights[0]["to"] == hud.slot_centre(0), "it flies from the token to the first slot")
	await process_frame
	_check(hud.shown_tokens == 0, "the slot stays empty while it flies")
	await _settle(hud)
	_check(hud.shown_tokens == 1 and hud.flights.is_empty(), "it fills the slot when it lands")

	# A full pocket leaves the token, so nothing flies.
	state.tokens = state.TOKEN_CAP
	state.tokens_changed.emit()
	await _settle(hud)
	var extra := Token.new(token_def)
	extra.position = token_at
	world.current.add_child(extra)
	world._collect(extra)
	_check(hud.flights.is_empty() and hud.shown_tokens == 3, "a full pocket sends nothing")
	extra.free()

	# Spending tokens empties slots from the last one.
	state.spend_token()
	await process_frame
	_check(hud.shown_tokens == 2 and hud._effects.has("t2"), "a spent token empties the point slot with a blink")
	await _settle(hud)

	# A health pip flies to the end of the bar, which grows to take it.
	world.warp_to("7")
	await process_frame
	var pip: Node2D = _things(world.current, "HealthPip")[0]
	world._collect(pip)
	_check(state.max_health == 1 and state.health == 1, "a pip makes the bar one long and full")
	_check(hud.flights.size() == 1 and hud.flights[0]["kind"] == &"pip" and hud.flights[0]["to"] == hud.pip_centre(0), "it flies to the first pip")
	_check(hud.shown_max == 0, "the bar waits for it")
	var grew := false
	for i in 2000:
		await process_frame
		grew = grew or hud._grow >= 0.0
		if not hud.busy():
			break
	_check(grew and hud.shown_max == 1 and hud.shown_health == 1, "the bar grows a square and it fills")

	# A death empties a pip; the bar keeps its length.
	state.max_health = 4
	state.health = 4
	hud.sync()
	_check(hud.shown_max == 4 and hud.shown_health == 4 and not hud.busy(), "a sync shows the state at once")
	state.spend_health()
	await process_frame
	_check(state.health == 3 and state.max_health == 4, "spending a pip keeps the bar's length")
	_check(hud.shown_health == 3 and hud._effects.has("p3"), "the last full pip blinks out")
	await _settle(hud)

	# Dying in a save room puts the player back there without a refill.
	state.health = 1
	state.health_changed.emit()
	await _settle(hud)
	world._place_in("s1", Vector2.INF, true)
	_check(state.health == 1, "respawning in a save room is not entering it")
	# Entering one fills the bar, a pip at a time.
	world._place_in("s1")
	_check(state.health == 4, "entering a save room refills every pip")
	await process_frame
	await process_frame
	_check(hud.shown_health > 1 and hud.shown_health < 4, "the pips fill one at a time (%d)" % hud.shown_health)
	await _settle(hud)
	_check(hud.shown_health == 4, "until the bar is full")

	# Loads and dev edits keep the length at least the pips held.
	state.load_dict({"health": 3})
	_check(state.max_health == 3, "an old save without a bar length gets one as long as its pips")
	state.load_dict({"health": 2, "max_health": 5})
	_check(state.max_health == 5 and state.health == 2, "a save keeps its length and its fill")
	state.set_loadout({"abilities": state.abilities.to_dict(), "tokens": 0, "health": 6, "max_health": 2})
	_check(state.max_health == 6, "a loadout with more pips than its bar lengthens it")

	world.free()
	print("HUD pass" if ok else "HUD fail")
	quit(0 if ok else 1)


func _layout(hud: Node) -> void:
	var H: GDScript = hud.get_script()
	_check(hud.pip_rect(0) == Rect2(H.ORIGIN + H.BAR + Vector2.ONE, Vector2(7, 7)), "the first pip starts at the heart's right tip")
	_check(hud.pip_rect(1).position.x - hud.pip_rect(0).position.x == 8.0, "pips share their borders")
	_check(hud.pip_rect(H.WRAP).position == hud.pip_rect(0).position + Vector2(0, 8), "the bar wraps under itself")
	_check(hud.plate_rect(0) == Rect2(H.ORIGIN, Vector2(17, 13)).grow(H.MARGIN), "with no pips the plate holds only the heart")
	_check(hud.plate_rect(4).end.x == H.ORIGIN.x + H.BAR.x + 33.0 + H.MARGIN, "four pips are 33 units long")
	_check(hud.plate_rect(100).end.x < 320.0 and hud.plate_rect(100).end.y < 180.0, "a long bar stays on the screen")
	_check(hud.slot_centre(0).x < hud.slot_centre(1).x and hud.slot_centre(2).y > hud.slot_centre(0).y, "tokens fill the left lobe, the right lobe, then the point")


func _settle(hud: Node) -> void:
	for i in 2000:
		await process_frame
		if not hud.busy():
			return


func _things(room: Room, type: String) -> Array[Node]:
	return room.get_children().filter(func(c: Node) -> bool: return c.get_script() != null and String(c.get_script().get_global_name()) == type and not c.is_queued_for_deletion())


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	ok = ok and cond
	return cond
