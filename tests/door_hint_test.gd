extends TestCase

## The map's door marks (a door used or not), the flags behind them, and the hint popup room 2's token shows.

const SAVE_TEMP := "user://door_hint_test.json"


func _initialize() -> void:
	watchdog()
	_run()


func _run() -> void:
	root.get_node("WorldData").ensure_loaded()
	var ok := _door_flags()
	ok = _old_save() and ok
	ok = _hint_data() and ok
	ok = await _hint_popup() and ok
	finish("DOOR HINT", ok)


func _gs() -> Node:
	return root.get_node("GameState")


func _door_flags() -> bool:
	var ok := true
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var state := _gs()
	state.reset()
	var info: RoomInfo = data.rooms["2"]
	var door: Door = null
	for ex in info.exits:
		if ex.dest_id == "s1":
			door = ex
	ok = check(door != null, "room 2 has a door to s1") and ok
	if door == null:
		return false
	state.use_door("2", door)
	var far: Door = data.rooms["s1"].door_by_rect(door.dest_rect)
	ok = check(state.door_used("2", door), "a used door is remembered") and ok
	ok = check(state.door_used("s1", far), "and so is the opening on the far side") and ok
	for ex in info.exits:
		if ex != door and ex.dest_id != "s1":
			ok = check(not state.door_used("2", ex), "another door is not marked") and ok
	var restored := Progression.from_dict(state.to_dict())
	ok = check(restored.flags.has(state.door_flag("2", door)), "the door flag is saved") and ok
	state.reset()
	ok = check(not state.door_used("2", door), "a new game forgets doors") and ok
	return ok


func _old_save() -> bool:
	var ok := true
	var state := _gs()
	state.reset()
	var old := {"visited": ["s1", "2"], "flags": ["token:r2_token"]}
	state.load_dict(old)
	var s1: RoomInfo = root.get_node("WorldData").rooms["s1"]
	var seeded := false
	for ex in s1.exits:
		if ex.dest_id == "2" and state.door_used("s1", ex):
			seeded = true
	ok = check(seeded, "a save with no door flags marks the doors between visited rooms") and ok
	var unseeded := true
	for ex in (root.get_node("WorldData").rooms["2"] as RoomInfo).exits:
		if ex.dest_id != "s1" and state.door_used("2", ex):
			unseeded = false
	ok = check(unseeded, "and not the doors to rooms that were never visited") and ok
	state.reset()
	return ok


func _hint_data() -> bool:
	var ok := true
	ok = check(Hints.problems().is_empty(), "the hints file is clean (%s)" % [Hints.problems()]) and ok
	ok = check(Hints.has("map") and Hints.title("map") == "THE MAP", "the map hint is titled") and ok
	var rows := Hints.rows("map")
	ok = check(rows.size() == 2 and rows[0]["id"] == "map", "and shows the map rows") and ok
	var bad := EntityDef.new()
	bad.type = "token"
	bad.id = "t"
	bad.props = {"hint": "nope"}
	ok = check(not Entities.problems(bad).is_empty(), "an unknown hint= is a room error") and ok
	bad.props = {"hint": "map"}
	ok = check(Entities.problems(bad).is_empty(), "a known hint= is accepted on a token") and ok
	var info: RoomInfo = root.get_node("WorldData").rooms["2"]
	var named := false
	for def in info.entities:
		if def.id == "r2_token" and def.props.get("hint", "") == "map":
			named = true
	ok = check(named, "room 2's token names the map hint") and ok
	return ok


func _hint_popup() -> bool:
	var ok := true
	var state := _gs()
	state.reset()
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "2"
	root.add_child(world)
	await process_frame
	var popup = world.power_popup
	var token: Node2D = null
	for child in world.current.get_children():
		if child is Token:
			token = child
	ok = check(token != null, "room 2 has its token") and ok
	if token == null:
		world.free()
		return false
	ok = check(not popup.opened, "no popup before the token is taken") and ok
	world._collect(token)
	await physics_frame
	await physics_frame
	ok = check(state.tokens == 1 and popup.opened and paused, "taking the token opens a popup and pauses") and ok
	ok = check(popup._title.text == "THE MAP" and not popup._name.visible, "it is the map hint, with no power name") and ok
	ok = check(not world.toast._label.visible, "and the toast stays quiet") and ok
	await create_timer(popup.MIN_SHOW + 0.1, true, false, true).timeout
	var event := InputEventKey.new()
	event.keycode = KEY_X
	event.physical_keycode = KEY_X
	event.pressed = true
	popup._input(event)
	ok = check(not popup.opened and not paused, "any key closes it and the game runs") and ok
	state.reset()
	world.free()
	return ok
