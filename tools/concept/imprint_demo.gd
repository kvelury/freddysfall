extends SceneTree

## CONCEPT ONLY, never merged. Plays a scripted demo of two Imprint aiming
## schemes in the real game, for recording with Godot's Movie Maker:
##   godot --path . --write-movie build/concept/frames/f.png --fixed-fps 60 --script tools/concept/imprint_demo.gd
## Headless with `-- --debug` it prints where Freddy lands instead.

const W := 32
const H := 18

var world: Node
var player: Player
var tool: Node
var overlay: Node2D
var hud: CanvasLayer
var debug := false
var scheme := "dash"
var aim := Vector2i.ZERO
var building := false
var build_sel_dir := "fwd"
var build_sel_ring := ConceptSlots.NEAR
var _was_grounded := true
var _tick := 0
var _busy_seen := false


func _initialize() -> void:
	debug = OS.get_cmdline_user_args().has("--debug")
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("FAIL watchdog at t=%d" % _tick)
		quit(1)
	)
	_run()


func _rooms() -> Dictionary:
	# Intro: open air over a floor.
	var intro := _grid([["#", 1, 15, 30, 17]], Vector2i(10, 14))
	# Gap: two ledges, spikes between.
	var gap := _grid([["#", 1, 15, 6, 17], ["#", 16, 15, 30, 17], ["^", 7, 16, 15, 16]], Vector2i(3, 14))
	# Catch: a high ledge, a long spike pit, a low ledge far off.
	var catch := _grid([["#", 1, 6, 7, 17], ["#", 19, 13, 30, 17], ["^", 8, 16, 18, 16]], Vector2i(4, 5))
	# Climb: a wall too high for a jump.
	var climb := _grid([["#", 1, 15, 30, 17], ["#", 17, 7, 30, 17]], Vector2i(8, 14))
	return {"90": intro, "91": gap, "92": catch, "93": climb}


func _grid(fills: Array, start: Vector2i) -> String:
	var rows: Array = []
	for y in H:
		var row := ""
		for x in W:
			row += "#" if x == 0 or y == 0 or x == W - 1 or y == H - 1 else "."
		rows.append(row)
	for f in fills:
		for y in range(f[2], f[4] + 1):
			var row: String = rows[y]
			for x in range(f[1], f[3] + 1):
				row[x] = f[0]
			rows[y] = row
	var row: String = rows[start.y]
	row[start.x] = "P"
	rows[start.y] = row
	return "\n".join(rows) + "\n"


func _run() -> void:
	var data: Node = root.get_node("WorldData")
	data.ensure_loaded()
	var errors: Array[String] = []
	var i := 0
	for id in _rooms():
		var info := RoomParser.parse_room(id, Vector2i(40 + i, 40), _rooms()[id], errors)
		info.solids = RoomParser.merge_solids(info.rows)
		data.rooms[id] = info
		i += 1
	for e in errors:
		print("room error: ", e)
	world = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "90"
	root.add_child(world)
	await process_frame
	var state: Node = root.get_node("GameState")
	state.abilities.imprint_unlocked = true
	player = world.get_node("Player")
	tool = world.get_node("Imprint")
	player.scripted = true
	tool.scripted = true
	_hide_tool_cursor()
	overlay = load("res://tools/concept/concept_overlay.gd").new()
	overlay.tool = tool
	world.add_child(overlay)
	hud = load("res://tools/concept/concept_hud.gd").new()
	world.add_child(hud)
	for name in ["DevPanel", "DebugOverlay", "Toast"]:
		world.get_node(name).visible = false
	physics_frame.connect(_on_tick)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var parts := arg.substr(7).split(":")
			scheme = parts[1] if parts.size() > 1 else "dash"
			await call("_shot_" + parts[0])
			quit()
			return

	await _title("IMPRINT AIMING", "concept: fixed slots around Freddy", 150)
	await _intro()
	await _title("A  DASH-STYLE", "hold a direction, press J (near) or K (far)", 150)
	scheme = "dash"
	hud.pad = false
	await _shot_gap()
	await _shot_catch()
	await _shot_climb()
	await _title("A  ON A CONTROLLER", "left stick aims, X = near, Y = far", 130)
	hud.pad = true
	await _shot_gap()
	await _title("C  BUILD MODE", "hold Shift: time slows to 30%, slots light up", 110)
	await _title("C  BUILD MODE", "steer to a slot, let go to place it", 110)
	scheme = "build"
	hud.pad = false
	await _shot_gap()
	await _shot_catch()
	await _title("C  ON A CONTROLLER", "hold LT, steer with the stick, let go", 130)
	hud.pad = true
	await _shot_climb()
	await _title("A or C?", "both will be switchable in the F2 dev panel", 180)
	_save_log()
	quit()


# --- Shots ---------------------------------------------------------------


func _intro() -> void:
	_enter("90", "THE SLOTS", "5 directions x near / far")
	hud.show_keys = false
	await _wait(30)
	_run_x(0.0)
	_jump()
	await _wait(3)
	await _until(func() -> bool: return player.velocity.y > -15.0)
	player.input_enabled = false
	_release_jump()
	overlay.labels = true
	for dir in ConceptSlots.DIRS:
		for ring in [ConceptSlots.NEAR, ConceptSlots.FAR]:
			overlay.ghosts.append({"dir": dir, "ring": ring, "style": "lit"})
			await _wait(12)
	await _wait(150)
	hud.set_caption("THE SLOTS", "facing left mirrors them")
	player.facing = -1
	await _wait(110)
	player.facing = 1
	hud.set_caption("THE SLOTS", "white = near (J),  grey = far (K)")
	await _wait(110)
	overlay.ghosts.clear()
	overlay.labels = false
	player.input_enabled = true
	await _wait(60)
	hud.show_keys = true


## Bridge a spike pit: forward-far from the edge, hop on, hop off.
func _shot_gap() -> void:
	_enter("91", _scheme_title(), "bridge a gap:  forward + far")
	await _wait(40)
	_run_x(1.0)
	_aim_set(1, 0)
	if scheme == "build":
		await _until(func() -> bool: return _x() >= 40.0)
		_build_hold()
		await _wait(12)
		_build_select("fwd", ConceptSlots.NEAR)
		await _wait(14)
		_build_select("fwd", ConceptSlots.FAR)
		await _until(func() -> bool: return _x() >= 50.0)
		_build_release()
	else:
		await _until(func() -> bool: return _x() >= 50.0)
		_press(ConceptSlots.FAR)
	await _until(func() -> bool: return _x() >= 58.0)
	_jump()
	await _wait(6)
	_release_jump()
	await _until(func() -> bool: return player.is_on_floor())
	await _wait(4)
	_jump()
	await _wait(2)
	await _until(func() -> bool: return player.is_on_floor())
	_release_jump()
	await _wait(20)
	_run_x(0.0)
	_aim_set(0, 0)
	await _wait(50)


## Walk off a high ledge, catch the fall with down + near, jump on.
func _shot_catch() -> void:
	_enter("92", _scheme_title(), "catch a fall:  down + near")
	await _wait(40)
	_run_x(1.0)
	if scheme == "build":
		await _until(func() -> bool: return _x() >= 80.0)
		_aim_set(1, 0)
		_build_hold()
		await _wait(10)
		_aim_set(0, 1)
		_build_select("down", ConceptSlots.NEAR)
		await _until(func() -> bool: return _y() >= 72.0)
		_build_release()
	else:
		await _until(func() -> bool: return _y() >= 70.0)
		_aim_set(1, 1)
		await _wait(3)
		_aim_set(0, 1)
		await _wait(3)
		_press(ConceptSlots.NEAR)
	await _until(func() -> bool: return player.is_on_floor())
	_aim_set(1, 0)
	await _wait(8)
	_jump()
	await _wait(2)
	await _until(func() -> bool: return player.is_on_floor())
	_release_jump()
	await _wait(20)
	_run_x(0.0)
	_aim_set(0, 0)
	await _wait(50)


## Climb a wall: up-forward + far, jump on it, jump to the top.
func _shot_climb() -> void:
	_enter("93", _scheme_title(), "climb a wall:  up-forward + far")
	await _wait(40)
	if scheme == "build":
		_aim_set(1, -1)
		_build_hold()
		await _wait(12)
		_build_select("upfwd", ConceptSlots.NEAR)
		await _wait(14)
		_build_select("upfwd", ConceptSlots.FAR)
		await _wait(16)
		_build_release()
	else:
		_aim_set(1, -1)
		await _wait(20)
		_press(ConceptSlots.FAR)
	await _wait(10)
	_aim_set(1, 0)
	_jump()
	await _wait(8)
	_run_x(1.0)
	await _until(func() -> bool: return player.is_on_floor())
	_release_jump()
	await _wait(4)
	_jump()
	await _wait(2)
	await _until(func() -> bool: return player.is_on_floor())
	_release_jump()
	await _wait(25)
	_run_x(0.0)
	_aim_set(0, 0)
	await _wait(50)


# --- Inputs ----------------------------------------------------------------


func _scheme_title() -> String:
	var name := "A  DASH-STYLE" if scheme == "dash" else "C  BUILD MODE"
	return name + ("  (pad)" if hud.pad else "")


func _enter(id: String, title: String, sub: String) -> void:
	world.warp_to(id)
	tool.clear(false)
	tool.sync_solids()
	_hide_tool_cursor()
	overlay.ghosts.clear()
	player.facing = 1
	aim = Vector2i.ZERO
	hud.set_caption(title, sub)
	hud.reset_keys()
	_was_grounded = true


func _run_x(x: float) -> void:
	player.scripted_x = x
	hud.keys["A"] = x < 0.0
	hud.keys["D"] = x > 0.0
	hud.stick.x = x if aim.x == 0 else float(aim.x)


func _aim_set(x: int, y: int) -> void:
	aim = Vector2i(x, y)
	hud.keys["W"] = y < 0
	hud.keys["S"] = y > 0
	hud.keys["D"] = x > 0 or player.scripted_x > 0.0
	hud.stick = Vector2(x, y).normalized() if aim != Vector2i.ZERO else Vector2(player.scripted_x, 0.0)
	if building:
		build_sel_dir = ConceptSlots.dir_from_input(x, y) if aim != Vector2i.ZERO else build_sel_dir


func _jump() -> void:
	player.scripted_jump_pressed = true
	player.scripted_jump_held = true
	hud.keys["Space"] = true


func _release_jump() -> void:
	player.scripted_jump_held = false
	hud.keys["Space"] = false


func _press(ring: String) -> void:
	var dir := ConceptSlots.dir_from_input(aim.x, aim.y)
	var ok := _place(dir, ring)
	var key := "J" if ring == ConceptSlots.NEAR else "K"
	hud.flash(key, 18)
	if debug:
		print("t=%d press %s %s at (%.1f, %.1f) -> %s %s" % [_tick, dir, ring, _x(), _y(), ok, tool.platforms[0].rect.position - world.current.position if ok else ""])


func _build_hold() -> void:
	building = true
	Engine.time_scale = 0.3
	hud.keys["Shift"] = true
	hud.slow = true
	build_sel_dir = ConceptSlots.dir_from_input(aim.x, aim.y)
	build_sel_ring = ConceptSlots.NEAR


func _build_select(dir: String, ring: String) -> void:
	build_sel_dir = dir
	build_sel_ring = ring
	# Tapping the direction again steps out to the far slot.
	for k in ["W", "A", "S", "D"]:
		if hud.keys[k]:
			hud.flash(k, 0)


func _build_release() -> void:
	var ok := _place(build_sel_dir, build_sel_ring)
	building = false
	Engine.time_scale = 1.0
	hud.keys["Shift"] = false
	hud.slow = false
	overlay.ghosts.clear()
	if debug:
		print("t=%d release %s %s at (%.1f, %.1f) -> %s %s" % [_tick, build_sel_dir, build_sel_ring, _x(), _y(), ok, tool.platforms[0].rect.position - world.current.position if ok else ""])


func _place(dir: String, ring: String) -> bool:
	var room: Room = world.current
	var local := player.global_position - room.position
	tool.scripted_cell = ConceptSlots.cell_for(local, player.facing, dir, ring, root.get_node("GameState").abilities.imprint_width)
	var ok: bool = tool.place()
	_hide_tool_cursor()
	if ok:
		overlay.ghosts.clear()
	return ok


## The tool's own cursor is moved off the room; the overlay draws the slots.
func _hide_tool_cursor() -> void:
	tool.scripted_cell = Vector2i(-100, -100)


func _x() -> float:
	return player.global_position.x - world.current.position.x


func _y() -> float:
	return player.global_position.y - world.current.position.y


func _on_tick() -> void:
	_tick += 1
	if overlay == null or world.current == null:
		return
	overlay.room = world.current
	overlay.player = player
	if building:
		overlay.ghosts.clear()
		for dir in ConceptSlots.DIRS:
			for ring in [ConceptSlots.NEAR, ConceptSlots.FAR]:
				var sel: bool = dir == build_sel_dir and ring == build_sel_ring
				overlay.ghosts.append({"dir": dir, "ring": ring, "style": "selected" if sel else "lit"})
	elif scheme == "dash" and hud.show_keys and player.input_enabled:
		overlay.ghosts.clear()
		if tool.platforms.is_empty() and world.current.info.id != "90":
			overlay.ghosts.append({"dir": ConceptSlots.dir_from_input(aim.x, aim.y), "ring": ConceptSlots.NEAR, "style": "aim"})
			overlay.ghosts.append({"dir": ConceptSlots.dir_from_input(aim.x, aim.y), "ring": ConceptSlots.FAR, "style": "aim_far"})
	elif scheme == "build" and not building:
		overlay.ghosts.clear()
	if debug:
		var g := player.is_on_floor()
		if g != _was_grounded:
			print("t=%d %s at (%.1f, %.1f)" % [_tick, "lands" if g else "leaves", _x(), _y()])
			_was_grounded = g
		if world.is_busy() and not _busy_seen:
			print("t=%d BUSY (death or door) at (%.1f, %.1f)" % [_tick, _x(), _y()])
		_busy_seen = world.is_busy()
		if OS.get_cmdline_user_args().has("--trace") and _tick % 3 == 0:
			print("  t=%d (%.1f, %.1f) v=(%.0f, %.0f)" % [_tick, _x(), _y(), player.velocity.x, player.velocity.y])


func _save_log() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/concept"))
	var f := FileAccess.open("res://build/concept/hud_log.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(hud.log))
	f.close()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, limit := 600) -> void:
	for i in limit:
		if cond.call():
			return
		await physics_frame
	print("t=%d timed out waiting" % _tick)


func _title(big: String, small: String, frames: int) -> void:
	hud.card_big = big
	hud.card_small = small
	hud.card = true
	await _wait(frames)
	hud.card = false
