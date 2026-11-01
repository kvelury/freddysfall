extends SceneTree

## The shape of a lash. First the pure curves in `TongueMotion` (the stats, the
## options, the way out and the way back), then every option through the real
## tongue in room 7, one physics tick at a time (`_move` is called directly, so
## the ticks are exact): the creep is slower than the snap, the way out never goes
## back and the way in never goes forward, the reach is exactly the tongue's
## length, a close hit comes no later than before, the tip cannot skip a wall at
## any speed, the stick holds the tip where it hit, and the starting values
## reproduce the old lash tick for tick.

const DT := 1.0 / 60.0
const WALL := "r7_pipwall"

var _ok := true
var _state: Node
var _dev: Node


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	_state = root.get_node("GameState")
	_dev = root.get_node("DevSession")
	_state.reset()
	_stats()
	_curves()
	_options()

	var world: Node = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "7"
	root.add_child(world)
	await process_frame
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	player.scripted = true
	tongue.scripted = true
	_dev.mode = _dev.Mode.DEV_TEST
	# The wall must outlast every lash here.
	_dev.wall_strength_override = 99
	var room: Room = world.current
	_stand(world, player)
	await physics_frame
	await physics_frame

	_today(tongue, player, room, world)
	for i in TongueMotion.preset_count():
		_option_in_play(i, tongue, player, room, world)
	_stick_follows(tongue, player, room, world)
	_at_once(tongue, player, world)
	_no_skipping(tongue, player, room, world)
	_length_does_not_delay(tongue, player, world)

	_dev.wall_strength_override = 0
	_dev.mode = _dev.Mode.NORMAL
	world.queue_free()
	await process_frame
	_state.reset()
	print("TONGUE MOTION %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


## The eight stats: starting values, floors, and the save round trip.
func _stats() -> void:
	var a := Abilities.new()
	_check(a.tongue_creep == 0.0 and a.tongue_creep_reach == 0.0 and a.tongue_ramp == 0.0 and a.tongue_strike == 1.0 and a.tongue_settle == 0.0 and a.tongue_stick == 0.0 and a.tongue_wobble == 0.0 and not a.tongue_pad, "the starting values are the steady way out and the accelerating snap back")
	var d := a.to_dict()
	for stat in ["tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick", "tongue_wobble", "tongue_pad"]:
		_check(Abilities.STATS.has(stat) and d.has(stat), "%s is registered and serialized" % stat)
	var odd := Abilities.from_dict({"tongue_creep": -1.0, "tongue_creep_reach": -2.0, "tongue_ramp": -0.5, "tongue_strike": 0.2, "tongue_settle": 5.0, "tongue_stick": -1.0, "tongue_wobble": -3.0})
	_check(odd.tongue_creep == 0.0 and odd.tongue_creep_reach == 0.0 and odd.tongue_ramp == 0.0 and odd.tongue_strike == 1.0 and odd.tongue_settle == 1.0 and odd.tongue_stick == 0.0 and odd.tongue_wobble == 0.0, "a save cannot hold a negative time or distance, a strike under 1 or a settle over 1")
	var tuned := Abilities.from_dict(TongueMotion.preset_values(4))
	var back := Abilities.from_dict(tuned.to_dict())
	_check(back.to_dict() == tuned.to_dict() and back.tongue_pad and is_equal_approx(back.tongue_wobble, 2.0), "the Full frog values round-trip through a save")
	_check(Abilities.from_dict({"tongue_unlocked": true}).to_dict()["tongue_strike"] == 1.0, "a save from before them loads with the starting values")
	var controls := DevCatalog.controls()
	for stat in ["tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick", "tongue_wobble"]:
		_check(controls.has(stat) and controls[stat]["type"] == "float" and controls[stat].has("min") and controls[stat].has("max") and controls[stat].has("step") and controls[stat].has("unit"), "%s has a bounded float dev control" % stat)
	_check(controls.has("tongue_pad") and controls["tongue_pad"]["type"] == "bool", "and the pad a bool one")
	_check(DevCatalog.problems().is_empty(), "every upgrade and stat still has a dev decision")


## The curves on their own.
func _curves() -> void:
	var a := Abilities.new()
	# The starting values: a steady 220 px/s, and the old return curve.
	_check(is_equal_approx(TongueMotion.out_speed(0.0, a), 220.0) and is_equal_approx(TongueMotion.out_speed(1.0, a), 220.0), "with the starting values the way out is a steady 220 px/s")
	_check(is_equal_approx(TongueMotion.out_distance(0.5, DT, a), 220.0 * DT), "and a tick is 220 / 60 px")
	_check(is_equal_approx(TongueMotion.back_duration(50.0, a), 50.0 / (3.5 * 220.0)), "the return takes extension / (snap * speed)")
	_check(TongueMotion.back_duration(0.0, a) == 0.0, "and nothing out takes no time")
	# The creep, ramp and strike.
	a.tongue_creep = 0.06
	a.tongue_creep_reach = 3.0
	a.tongue_ramp = 0.04
	a.tongue_strike = 4.0
	_check(is_equal_approx(TongueMotion.out_speed(0.0, a), 50.0) and is_equal_approx(TongueMotion.out_speed(0.059, a), 50.0), "the creep is steady (3 px in 0.06 s)")
	_check(is_equal_approx(TongueMotion.out_speed(0.08, a), (50.0 + 880.0) * 0.5) and is_equal_approx(TongueMotion.out_speed(0.5, a), 880.0), "the speed climbs through the ramp to speed times strike, and holds")
	var sum := 0.0
	var steps := 600
	for k in steps:
		sum += TongueMotion.out_speed((float(k) + 0.5) * 0.0005, a) * 0.0005
	_check(absf(sum - TongueMotion.out_distance(0.0, 0.3, a)) < 0.05, "a distance is the area under the speed (%.3f px against %.3f)" % [TongueMotion.out_distance(0.0, 0.3, a), sum])
	var split := 0.0
	var t := 0.0
	for k in 18:
		split += TongueMotion.out_distance(t, DT, a)
		t += DT
	_check(absf(split - TongueMotion.out_distance(0.0, 18.0 * DT, a)) < 0.001, "and ticks add up to the same distance as one long step")
	_check(is_equal_approx(TongueMotion.out_distance(0.0, 0.06, a), 3.0), "the creep covers exactly its reach")
	# The return.
	for snap in [1.0, 2.5, 3.5, 6.0, 10.0]:
		for settle in [0.0, 0.5, 1.0]:
			var r := Abilities.new()
			r.tongue_snap = snap
			r.tongue_settle = settle
			var monotone := true
			var last := 2.0
			for k in 101:
				var rem := TongueMotion.remaining(float(k) / 100.0, r)
				monotone = monotone and rem <= last + 1e-12
				last = rem
			_check(is_equal_approx(TongueMotion.remaining(0.0, r), 1.0) and is_equal_approx(TongueMotion.remaining(1.0, r), 0.0) and monotone, "the return runs from 1 to 0 and never rises (snap %.1f, settle %.1f)" % [snap, settle])
	var steady := Abilities.new()
	steady.tongue_snap = 1.0
	_check(is_equal_approx(TongueMotion.remaining(0.25, steady), 0.75), "a snap of 1 is a steady return")
	var spring := Abilities.new()
	spring.tongue_settle = 1.0
	var fast_start := 1.0 - TongueMotion.remaining(0.35, spring)
	var slow_end := TongueMotion.remaining(0.85, spring) - TongueMotion.remaining(1.0, spring)
	_check(fast_start > 0.5 and slow_end < 0.05, "the spring return is more than half done in the first 35%% and eases in (%.2f done at 35%%, %.3f left at 85%%)" % [fast_start, slow_end])
	_check(TongueMotion.seat_offset(0.0, 2.0) == 0.0 and absf(TongueMotion.seat_offset(1.0, 2.0)) < 1e-9 and TongueMotion.seat_offset(0.4, 2.0) > 0.0 and TongueMotion.seat_offset(0.3, 0.0) == 0.0, "the wobble starts and ends at 0, pops out between, and is off at 0")


## The options as data.
func _options() -> void:
	_check(TongueMotion.preset_count() == 5, "there are five options")
	var names: Array[String] = []
	for i in TongueMotion.preset_count():
		names.append(TongueMotion.preset_name(i))
	_check(names == ["Today", "Creep & snap", "Whip", "Sticky", "Full frog"], "named Today, Creep & snap, Whip, Sticky and Full frog (%s)" % [names])
	var today := Abilities.new().to_dict()
	var matches := true
	for stat in TongueMotion.preset_values(0):
		matches = matches and today[stat] == TongueMotion.preset_values(0)[stat]
	_check(matches and TongueMotion.find_preset(today) == 0, "Today is exactly the starting values")
	for i in TongueMotion.preset_count():
		var sample := DevCatalog.defaults()
		for stat in TongueMotion.preset_values(i):
			sample["abilities"][stat] = TongueMotion.preset_values(i)[stat]
		_check(DevCatalog.validate(sample).is_empty() and TongueMotion.find_preset(sample["abilities"]) == i, "%s passes the dev limits and is found again" % names[i])
		var copy := TongueMotion.preset_values(i)
		copy["tongue_speed"] = 1.0
		_check(TongueMotion.preset_values(i)["tongue_speed"] == 220.0, "%s hands out a copy, not its own table" % names[i])
	var tuned := TongueMotion.preset_values(1)
	tuned["tongue_strike"] = 2.0
	var sample := Abilities.new().to_dict()
	sample.merge(tuned, true)
	_check(TongueMotion.find_preset(sample) == -1, "a tuned set matches no option")


## The tongue as Today, against the lash it replaced.
func _today(tongue: Node, player: Player, room: Room, world: Node) -> void:
	for facing in [1, -1]:
		var run := _lash(tongue, player, TongueMotion.preset_values(0), facing)
		var xs: Array = run["xs"]
		var peak := _peak(xs)
		var index := xs.find(peak)
		var expected: Array = _old_lash(peak)
		var same := xs.size() == expected.size()
		for k in mini(xs.size(), expected.size()):
			same = same and absf(float(xs[k]) - float(expected[k])) < 0.0001
		_check(same, "Today goes out and comes back tick for tick as the old lash did (facing %d, %.1f px, %d ticks)" % [facing, peak, xs.size()])
		_check(index == int(ceil(peak / (220.0 * DT) - 0.0001)) - 1, "and takes %d ticks out" % (index + 1))
	_check(_damage(room) == 1, "the left lash hit the wall once")


## One option, in play.
func _option_in_play(i: int, tongue: Node, player: Player, room: Room, world: Node) -> void:
	var name := TongueMotion.preset_name(i)
	var values := TongueMotion.preset_values(i)
	var snap_speed: float = values["tongue_speed"] * values["tongue_strike"]
	# A miss to the right: the full 50 px.
	var miss := _lash(tongue, player, values, 1)
	var xs: Array = miss["xs"]
	var phases: Array = miss["phases"]
	_check(is_equal_approx(_peak(xs), 50.0) and not tongue.active, "%s: a lash that meets nothing reaches exactly the tongue's length and comes home" % name)
	_check(not phases.has(tongue.Phase.STICK), "%s: a miss does not stick" % name)
	var peak_at := xs.find(_peak(xs))
	var out_ok := true
	for k in range(1, peak_at + 1):
		out_ok = out_ok and float(xs[k]) >= float(xs[k - 1]) - 1e-9
	var legs: Array = []
	var back_ok := true
	var first_back := peak_at + 1
	var last_back := xs.size() - 1
	if values["tongue_wobble"] > 0.0:
		# The seating bump follows the return's last tick.
		last_back = phases.find(tongue.Phase.SEAT)
		last_back = last_back - 1 if last_back > 0 else xs.size() - 1
	for k in range(first_back, last_back + 1):
		back_ok = back_ok and float(xs[k]) <= float(xs[k - 1]) + 1e-9
		legs.append(float(xs[k - 1]) - float(xs[k]))
	_check(out_ok and back_ok, "%s: the way out never goes back and the way in never goes forward" % name)
	var jump := 0.0
	for k in range(1, xs.size()):
		jump = maxf(jump, absf(float(xs[k]) - float(xs[k - 1])))
	_check(jump <= snap_speed * DT + 1e-6 or jump <= 50.0, "%s: no tick moves the tip more than its reach (%.1f px)" % [name, jump])
	# The creep is slower than the snap.
	if values["tongue_creep"] > 0.0:
		var first := float(xs[0])
		var fastest := 0.0
		for k in range(1, peak_at + 1):
			fastest = maxf(fastest, float(xs[k]) - float(xs[k - 1]))
		_check(first < fastest * 0.5, "%s: the creep (%.2f px a tick) is slower than the snap (%.2f px a tick)" % [name, first, fastest])
	# A spring return is fastest early and eases in.
	if values["tongue_settle"] >= 1.0:
		var top := 0
		for k in legs.size():
			if float(legs[k]) > float(legs[top]):
				top = k
		_check(top <= legs.size() / 2 and float(legs[legs.size() - 1]) < float(legs[top]), "%s: the return is quickest early (tick %d of %d) and slower at the end" % [name, top + 1, legs.size()])
	# The wobble only follows the return when it is on.
	_check(phases.has(tongue.Phase.SEAT) == (values["tongue_wobble"] > 0.0), "%s: it seats with a wobble only when the wobble is on" % name)
	if values["tongue_wobble"] > 0.0:
		var seat_ok := true
		for k in xs.size():
			if phases[k] == tongue.Phase.SEAT:
				seat_ok = seat_ok and float(xs[k]) >= 0.0 and float(xs[k]) <= values["tongue_wobble"]
		_check(seat_ok and float(xs[xs.size() - 1]) == 0.0, "%s: the wobble stays between 0 and %.1f px and ends at 0" % [name, values["tongue_wobble"]])
	_check(tongue.cooldown_left > 0.0, "%s: the cooldown starts when the tongue is home" % name)

	# A hit on the wall to the left, 30 px away.
	var before := _damage(room)
	var hit := _lash(tongue, player, values, -1)
	xs = hit["xs"]
	phases = hit["phases"]
	var out_ticks := 0
	for p in phases:
		if p == tongue.Phase.OUT:
			out_ticks += 1
	_check(_damage(room) == before + 1, "%s: one lash hits the wall once" % name)
	_check(_peak(xs) < 40.0 and _peak(xs) > 25.0, "%s: and the tip stops at the wall (%.1f px)" % [name, _peak(xs)])
	if i > 0:
		_check(out_ticks <= 9, "%s: a wall 30 px away is hit in %d ticks, no later than the 9 it took before" % [name, out_ticks])
	var stuck := 0
	for p in phases:
		if p == tongue.Phase.STICK:
			stuck += 1
	var wanted := int(ceil(values["tongue_stick"] / DT - 0.0001)) if values["tongue_stick"] > 0.0 else 0
	_check(stuck == wanted, "%s: it sticks to the wall for %d ticks (%d)" % [name, wanted, stuck])
	if stuck > 0:
		var held := true
		for k in xs.size():
			if phases[k] == tongue.Phase.STICK:
				held = held and is_equal_approx(float(xs[k]), _peak(xs))
		_check(held, "%s: and the tip holds where it hit" % name)
	var drawn_pad := false
	if values["tongue_pad"] and values["tongue_stick"] > 0.0:
		var body := player.get_node("Visual") as PlayerBody
		var pad := body.pad_rect(_peak(xs))
		var line := body.tongue_rect(_peak(xs))
		drawn_pad = pad.size == Vector2(2, 3) and pad.position == pad.position.round() and pad.get_center().y == line.get_center().y and pad.position.x == line.position.x
	_check(drawn_pad == (values["tongue_pad"] and values["tongue_stick"] > 0.0), "%s: the pad is a whole-pixel 2 x 3 box centred on the line at the tip" % name)
	_check(tongue.retracting == false and not tongue.active, "%s: and the tongue is home" % name)
	# The tip was pad-free when it did not stick.
	_check(room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) != null, "%s: and the wall still stands (strength 99)" % name)


## The tip stays on the wall when the player moves under it.
func _stick_follows(tongue: Node, player: Player, room: Room, world: Node) -> void:
	_apply(TongueMotion.preset_values(3))
	_stand(world, player)
	player.facing = -1
	tongue.cooldown_left = 0.0
	tongue.lash()
	var guard := 0
	while tongue.phase != tongue.Phase.STICK and tongue.active and guard < 100:
		tongue._move(DT)
		guard += 1
	_check(tongue.phase == tongue.Phase.STICK, "Sticky: the tongue sticks to the wall")
	var tip_x: float = tongue.tip().x
	var out: float = tongue.extension
	player.global_position.x -= 2.0
	tongue._move(DT)
	_check(is_equal_approx(tongue.tip().x, tip_x) and is_equal_approx(tongue.extension, out - 2.0), "Sticky: the player stepping 2 px toward the wall shortens the tongue and leaves the tip where it hit")
	tongue.end()
	tongue.cooldown_left = 0.0
	_stand(world, player)


## A lash made with the player pressed to the wall hits at once: no creep, no stick.
func _at_once(tongue: Node, player: Player, world: Node) -> void:
	var room: Room = world.current
	var reach := _peak(_lash(tongue, player, TongueMotion.preset_values(3), -1)["xs"])
	_stand(world, player)
	_apply(TongueMotion.preset_values(3))
	player.facing = -1
	var before := _damage(room)
	tongue.cooldown_left = 0.0
	player.global_position.x -= reach
	var lashed: bool = tongue.lash()
	_check(lashed and _damage(room) == before + 1 and tongue.phase == tongue.Phase.BACK and tongue.extension == 0.0, "Sticky: pressed to the wall, a lash hits at once, with no creep, no stick and nothing to wait out")
	tongue._move(DT)
	_check(not tongue.active, "and is over on the next tick")
	tongue.cooldown_left = 0.0
	_stand(world, player)


## A tongue this fast would skip a thin wall if it went in one step.
func _no_skipping(tongue: Node, player: Player, room: Room, world: Node) -> void:
	var values := TongueMotion.preset_values(1)
	values["tongue_speed"] = 2000.0
	values["tongue_strike"] = 10.0
	var before := _damage(room)
	var run := _lash(tongue, player, values, -1)
	_check(_damage(room) == before + 1 and _peak(run["xs"]) < 40.0, "at 2000 px/s times 10 the tip still stops at the wall (%.1f px) and hits it once" % _peak(run["xs"]))
	_check(not tongue.active, "and the lash ends")


## A longer tongue does not delay a close hit.
func _length_does_not_delay(tongue: Node, player: Player, world: Node) -> void:
	for i in TongueMotion.preset_count():
		var values := TongueMotion.preset_values(i)
		var short := _lash(tongue, player, values, -1)
		var long_values := values.duplicate()
		long_values["tongue_length"] = 100.0
		var long := _lash(tongue, player, long_values, -1)
		var short_out := _ticks_out(short)
		var long_out := _ticks_out(long)
		_check(short_out == long_out and short["xs"].size() == long["xs"].size(), "%s: a 100 px tongue hits the wall 30 px away as soon as a 50 px one (%d ticks, %d)" % [TongueMotion.preset_name(i), long_out, short_out])


## The lash the code made before the motion became tunable: a steady 220 px/s out
## to `peak`, then constant acceleration from 220 px/s averaging 3.5 times that.
func _old_lash(peak: float) -> Array:
	var xs := []
	var ext := 0.0
	while true:
		ext = minf(ext + 220.0 * DT, peak)
		xs.append(ext)
		if ext >= peak:
			break
	var speed := 220.0
	var accel := 2.0 * 3.5 * 2.5 * speed * speed / peak
	while true:
		ext -= speed * DT + 0.5 * accel * DT * DT
		speed += accel * DT
		if ext <= 0.0:
			xs.append(0.0)
			break
		xs.append(ext)
	return xs


## Sets the abilities to the starting ones with Tongue Lash found and `values` on top.
func _apply(values: Dictionary) -> void:
	var abilities := Abilities.new()
	abilities.tongue_unlocked = true
	for stat in values:
		abilities.set(stat, values[stat])
	_state.abilities = abilities


## Lashes with `values` and plays the tongue out one tick at a time. Returns the
## extension after each tick (`xs`) and which phase handled it (`phases`).
func _lash(tongue: Node, player: Player, values: Dictionary, facing: int) -> Dictionary:
	_apply(values)
	tongue.clear()
	tongue.cooldown_left = 0.0
	player.facing = facing
	var lashed: bool = tongue.lash()
	var xs: Array = []
	var phases: Array = []
	var guard := 0
	while tongue.active and guard < 400:
		var phase: int = tongue.phase
		tongue._move(DT)
		xs.append(tongue.extension)
		phases.append(phase)
		guard += 1
	return {"xs": xs, "phases": phases, "lashed": lashed}


func _ticks_out(run: Dictionary) -> int:
	var n := 0
	for p in run["phases"]:
		if p == 0:
			n += 1
	return n


func _peak(xs: Array) -> float:
	var top := 0.0
	for x in xs:
		top = maxf(top, float(x))
	return top


func _stand(world: Node, player: Player) -> void:
	var room: Room = world.current
	player.place(room.position + Grid.cell_center(Vector2i(24, 34)), room.world_rects())
	player.facing = 1


func _damage(room: Room) -> int:
	var wall := room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2)))
	return wall.damage if wall != null else -1


func _check(cond: bool, label: String) -> void:
	print(("ok   " if cond else "FAIL ") + label)
	_ok = cond and _ok
