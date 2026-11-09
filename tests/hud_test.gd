extends TestCase

## The health and token HUD. Its layout, how it follows GameState, a pickup
## flying in before it counts, a death emptying a pip, a save room filling the
## bar again, and a sync showing the state at once with nothing animating.

const TEMP := "user://hud_test.json"


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	var state: Node = root.get_node("GameState")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = false
	state.reset()
	var B: int = Progression.BASE_HEALTH

	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "2"
	root.add_child(world)
	await process_frame
	var hud: Node = world.get_node("Hud")
	_layout(hud)

	check(hud.layer == 9 and hud.scale == Vector2.ONE * float(Display.RENDER_SCALE), "the HUD is a UI layer under the map, drawn at the render scale")
	check(hud.shown_tokens == 0 and hud.shown_max == B and hud.shown_health == B and not hud.busy(), "a new game shows no diamonds and the base hearts, full")
	check(hud.to_ui(world.camera.position) == Vector2(160, 90), "the camera's centre is the middle of the UI (%s)" % hud.to_ui(world.camera.position))

	# A token flies in, and only counts when it lands.
	var token: Node2D = _things(world.current, "Token")[0]
	var from: Vector2 = hud.to_ui(token.global_position)
	var token_def: EntityDef = token.def
	var token_at := token.position
	world._collect(token)
	check(state.tokens == 1 and hud.flights.size() == 1, "taking a token starts one flight")
	check(hud.flights[0]["from"] == from and hud.flights[0]["to"] == hud.slot_centre(0), "it flies from the token to the first diamond")
	await process_frame
	check(hud.shown_tokens == 0 and hud.tab_slots() == 0, "no diamond and no tab appear while it flies")
	await _settle(hud)
	check(hud.shown_tokens == 1 and hud.flights.is_empty(), "the diamond appears when it lands")
	check(hud.tab_slots() == 1, "the tab appears with the first token")

	# A full pocket leaves the token, so nothing flies.
	state.tokens = state.TOKEN_CAP
	state.tokens_changed.emit()
	await _settle(hud)
	var extra := Token.new(token_def)
	extra.position = token_at
	world.current.add_child(extra)
	world._collect(extra)
	check(hud.flights.is_empty() and hud.shown_tokens == 3, "a full pocket sends nothing")
	extra.free()

	# Spending tokens empties slots from the last one.
	state.spend_token()
	await process_frame
	check(hud.shown_tokens == 2 and hud._effects.has("t2"), "a spent token blinks its diamond out")
	check(hud.tab_slots() == 3, "the tab keeps the spent slot while it blinks")
	await _settle(hud)
	check(hud.tab_slots() == 2, "the tab shrinks once the blink is over")

	# A health pip flies to a new heart at the end of the frame, which grows to take it.
	world.warp_to("7")
	await process_frame
	var pip: Node2D = _things(world.current, "HealthPip")[0]
	world._collect(pip)
	check(state.max_health == B + 1 and state.health == B + 1, "a pip makes the frame a heart longer and full")
	check(hud.flights.size() == 1 and hud.flights[0]["kind"] == &"pip" and hud.flights[0]["to"] == hud.pip_centre(B), "it flies to the new heart")
	check(hud.shown_max == B, "the frame waits for it")
	var grew := false
	for i in 2000:
		await process_frame
		grew = grew or hud._grow >= 0.0
		if not hud.busy():
			break
	check(grew and hud.shown_max == B + 1 and hud.shown_health == B + 1, "the frame grows a heart and it fills")

	# A death empties a pip; the bar keeps its length.
	state.max_health = 4
	state.health = 4
	hud.sync()
	check(hud.shown_max == 4 and hud.shown_health == 4 and not hud.busy(), "a sync shows the state at once")
	state.spend_health()
	await process_frame
	check(state.health == 3 and state.max_health == 4, "spending a pip keeps the bar's length")
	check(hud.shown_health == 3 and hud._effects.has("p3"), "the last full pip blinks out")
	await _settle(hud)

	# Dying in a save room puts the player back there without a refill.
	state.health = 1
	state.health_changed.emit()
	await _settle(hud)
	world._place_in("s1", Vector2.INF, true)
	check(state.health == 1, "respawning in a save room is not entering it")
	# Entering one fills the bar, a pip at a time.
	world._place_in("s1")
	check(state.health == 4, "entering a save room refills every pip")
	await process_frame
	await process_frame
	check(hud.shown_health > 1 and hud.shown_health < 4, "the pips fill one at a time (%d)" % hud.shown_health)
	await _settle(hud)
	check(hud.shown_health == 4, "until the bar is full")

	# Loads and dev edits keep the length at least the hearts held.
	state.load_dict({"health": 3})
	check(state.max_health == 3 + B and state.health == 3 + B, "an old save without a base heart gets them, full")
	state.load_dict({"health_base": B, "health": 2, "max_health": 5})
	check(state.max_health == 5 and state.health == 2, "a save keeps its length and its fill")
	state.set_loadout({"abilities": state.abilities.to_dict(), "tokens": 0, "health": 6, "max_health": 2})
	check(state.max_health == 6, "a loadout with more hearts than its frame lengthens it")

	world.free()
	print("HUD pass" if passed() else "HUD fail")
	quit(0 if passed() else 1)


func _layout(hud: Node) -> void:
	var H: GDScript = hud.get_script()
	var origin: Vector2 = H.ORIGIN
	check(hud.pip_rect(0) == Rect2(origin + Vector2(1, 1), Vector2(7, 6)), "the first heart is one unit in from the rectangle's top and left")
	check(hud.pip_rect(1).position.x - hud.pip_rect(0).position.x == 9.0, "hearts are 9 units apart")
	check(hud.pip_rect(H.WRAP).position == hud.pip_rect(0).position + Vector2(0, H.ROW_STEP), "the rectangle wraps under itself")
	check(H.BAR_HEIGHT == 8.0 and H.PAD == 1.0, "the rectangle is 8 units tall, with one unit of bar around the hearts")
	var rects: Array[Rect2] = hud.frame_rects(0, 9)
	check(rects[1] == Rect2(origin, Vector2(9, 8)), "one heart makes a 9 x 8 rectangle: 7 units of heart and one at each side")
	check(rects[0] == Rect2(origin - Vector2.ONE, Vector2(9, 8)), "the shadow is the same size, one unit up and left, so the bottom and right edges are clean")
	var heart0: Rect2 = hud.pip_rect(0)
	check(heart0.position.x - rects[1].position.x == 1.0 and rects[1].end.x - heart0.end.x == 1.0 and heart0.position.y - rects[1].position.y == 1.0 and rects[1].end.y - heart0.end.y == 1.0, "a heart has one unit of bar on every side")
	check(hud.frame_rects(0, 9 * 5)[1].size.x == 45.0, "five hearts make the rectangle 45 units wide")
	check(hud.slot_centre(0) == origin + Vector2(2, 9), "slot 0's diamond sits in the tab, one unit in from the rectangle's left edge and right under its bottom")
	check(hud.slot_centre(1) - hud.slot_centre(0) == Vector2(4, 0) and hud.slot_centre(2) - hud.slot_centre(0) == Vector2(8, 0), "slots 1 and 2 follow to the right, 4 units apart, so a unit of bar shows between diamonds")
	check(hud.tab_rects(0).is_empty(), "with no token held there is no tab")
	for n in [1, 2, 3]:
		var tab: Array[Rect2] = hud.tab_rects(n)
		check(tab[1] == Rect2(origin + Vector2(0, 8), Vector2(4 * n + 1, 4)), "%d token(s) make a tab %d units wide and 4 tall, flush under the bar and level with its left edge" % [n, 4 * n + 1])
		check(tab[0] == Rect2(tab[1].position - Vector2.ONE, tab[1].size), "the tab's shadow is one unit up and left, like the rectangle's")
		var last: Vector2 = hud.slot_centre(n - 1)
		check(last.x - 1.0 == tab[1].position.x + 1.0 + 4.0 * (n - 1) and tab[1].end.x - (last.x + 2.0) == 1.0, "the last diamond has one unit of bar before and after it")
		check(last.y - 1.0 == tab[1].position.y and tab[1].end.y - (last.y + 2.0) == 1.0, "a diamond sits right under the rectangle, with one unit of bar below it")
	check(H.ROW_STEP >= H.BAR_HEIGHT + H.TAB_HEIGHT + 2.0, "a wrapped rectangle's shadow clears the tab by a unit")
	check(hud.bounds(0) == hud.bounds(1) and hud.bounds(0).position == origin - Vector2.ONE, "the bounds start at the shadow, with no hearts or tokens")
	check(hud.bounds(1).end == origin + Vector2(13, 12), "the bounds cover the full three-token tab, held or not, which is wider than a one-heart rectangle")
	check(hud.bounds(4).end.x == origin.x + 9.0 * 4, "four hearts make the rectangle 9 units longer each")
	check(hud.bounds(31).end.y == origin.y + H.ROW_STEP + H.BAR_HEIGHT, "a wrapped rectangle's bounds reach the second rectangle's bottom")
	check(hud.bounds(100).end.x < 320.0 and hud.bounds(100).end.y < 180.0, "a long rectangle stays on the screen")
	check(hud.bounds(100).position.x >= 10.0 and hud.bounds(100).position.y >= 10.0, "the shadow stays clear of a room's outer wall")
	check(hud._fill_colour("t0", true) == H.GOLD and hud._fill_colour("p0", true) == H.RED, "a token fills gold and a full heart red")
	hud._effects["t0"] = {"kind": &"pop", "left": 1.0}
	hud._effects["p0"] = {"kind": &"pop", "left": 1.0}
	check(hud._fill_colour("t0", true) == Color.WHITE and hud._fill_colour("p0", true) == Color.WHITE, "a landing token or heart flashes white first")
	hud._effects.clear()
	check(hud._fill_colour("p0", false) == Color.BLACK, "an empty heart is black inside")
	check(hud.heart_look(0) == ["hud_heart_empty", H.INK] and hud.heart_look(Progression.BASE_HEALTH) == ["hud_heart", H.INK], "a full heart is a black outline over the red bar and an empty heart is solid black")
	hud._effects["p0"] = {"kind": &"pop", "left": 1.0}
	check(hud.heart_look(0) == ["hud_heart", Color.WHITE], "a landing heart flashes solid white")
	hud._effects.clear()
	check(hud.shown_tokens == 0 and hud.slot_centre(0).x < hud.slot_centre(1).x and hud.slot_centre(1).x < hud.slot_centre(2).x, "with no token held nothing is drawn, and diamonds fill left to right")


func _settle(hud: Node) -> void:
	for i in 2000:
		await process_frame
		if not hud.busy():
			return


func _things(room: Room, type: String) -> Array[Node]:
	return room.get_children().filter(func(c: Node) -> bool: return c.get_script() != null and String(c.get_script().get_global_name()) == type and not c.is_queued_for_deletion())
