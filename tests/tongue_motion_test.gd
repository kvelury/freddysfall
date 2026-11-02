extends SceneTree

## The shape of a lash. First the pure curves in `TongueMotion` (the stats, the
## way out and the way back), then two lashes through the real tongue in room 7,
## one physics tick at a time (`_move` is called directly, so the ticks are
## exact): the starting values (a frog's: a creep, a snap, a stick and a spring
## return) and the steady lash that came before, kept as explicit values so the
## model's whole range stays covered. For each: the creep is slower than the snap, the way out never goes
## back and the way in never goes forward, the reach is exactly the tongue's
## length, a close hit comes no later than before, the tip cannot skip a wall at
## any speed, the stick holds the tip where it hit, and the starting values
## reproduce the old lash tick for tick.

const DT := 1.0 / 60.0
const WALL := "r7_pipwall"
## PR #67's lash: a steady 220 px/s out, then an accelerating snap back at 3.5 times that.
const STEADY := {
	"tongue_speed": 220.0, "tongue_snap": 3.5, "tongue_creep": 0.0, "tongue_creep_reach": 0.0,
	"tongue_ramp": 0.0, "tongue_strike": 1.0, "tongue_settle": 0.0, "tongue_stick": 0.0, "tongue_pad": false,
}

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

	_steady_is_the_old_lash(tongue, player, room)
	_in_play("Frog", {}, tongue, player, room)
	_in_play("Steady", STEADY, tongue, player, room)
	_stick_follows(tongue, player, world)
	_at_once(tongue, player, world)
	_no_skipping(tongue, player, room)
	_length_does_not_delay(tongue, player)

	_dev.wall_strength_override = 0
	_dev.mode = _dev.Mode.NORMAL
	world.queue_free()
	await process_frame
	_state.reset()
	print("TONGUE MOTION %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


## The seven stats: starting values, floors, and the save round trip.
func _stats() -> void:
	var a := Abilities.new()
	_check(is_equal_approx(a.tongue_creep, 0.065) and is_equal_approx(a.tongue_creep_reach, 4.0) and is_equal_approx(a.tongue_ramp, 0.05) and is_equal_approx(a.tongue_strike, 3.9) and a.tongue_settle == 1.0 and is_equal_approx(a.tongue_stick, 0.05) and a.tongue_pad and is_equal_approx(a.tongue_snap, 2.5) and is_equal_approx(a.tongue_speed, 220.0), "the starting values are the chosen frog's tongue: a 4-tick creep over 4 px, a snap to 3.9 times 220 px/s, a 3-tick stick with a pad, a spring return at a 2.5 snap")
	var d := a.to_dict()
	for stat in ["tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick", "tongue_pad"]:
		_check(Abilities.STATS.has(stat) and d.has(stat), "%s is registered and serialized" % stat)
	_check(not Abilities.STATS.has("tongue_wobble") and not d.has("tongue_wobble"), "the wobble, which the chosen tongue does not use, is gone")
	var odd := Abilities.from_dict({"tongue_creep": -1.0, "tongue_creep_reach": -2.0, "tongue_ramp": -0.5, "tongue_strike": 0.2, "tongue_settle": 5.0, "tongue_stick": -1.0})
	_check(odd.tongue_creep == 0.0 and odd.tongue_creep_reach == 0.0 and odd.tongue_ramp == 0.0 and odd.tongue_strike == 1.0 and odd.tongue_stick == 0.0, "a save cannot hold a negative time or distance or a strike under 1")
	var steady := Abilities.from_dict(STEADY)
	var back := Abilities.from_dict(steady.to_dict())
	_check(back.to_dict() == steady.to_dict() and not back.tongue_pad and back.tongue_stick == 0.0 and is_equal_approx(back.tongue_snap, 3.5), "the steady values round-trip through a save")
	_check(Abilities.from_dict({"tongue_unlocked": true}).to_dict() == Abilities.new().to_dict().merged({"tongue_unlocked": true}, true), "a save from before the shape stats loads with the starting values")
	var controls := DevCatalog.controls()
	for stat in ["tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick"]:
		_check(controls.has(stat) and controls[stat]["type"] == "float" and controls[stat].has("min") and controls[stat].has("max") and controls[stat].has("step") and controls[stat].has("unit"), "%s has a bounded float dev control" % stat)
	_check(controls.has("tongue_pad") and controls["tongue_pad"]["type"] == "bool", "and the pad a bool one")
	_check(DevCatalog.problems().is_empty(), "every upgrade and stat still has a dev decision")
	var in_range := DevCatalog.defaults()
	_check(DevCatalog.validate(in_range).is_empty(), "and the starting values are inside every limit")


## The curves on their own.
func _curves() -> void:
	var a := Abilities.from_dict(STEADY)
	# The steady values: a steady 220 px/s, and the old return curve.
	_check(is_equal_approx(TongueMotion.out_speed(0.0, a), 220.0) and is_equal_approx(TongueMotion.out_speed(1.0, a), 220.0), "with the steady values the way out is a steady 220 px/s")
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
	var over := Abilities.from_dict(STEADY)
	over.tongue_settle = 5.0
	var full := Abilities.from_dict(STEADY)
	full.tongue_settle = 1.0
	_check(is_equal_approx(TongueMotion.remaining(0.3, over), TongueMotion.remaining(0.3, full)), "a settle over 1 is held at 1 where the curve is worked out")
	var steady := Abilities.from_dict(STEADY)
	steady.tongue_snap = 1.0
	_check(is_equal_approx(TongueMotion.remaining(0.25, steady), 0.75), "a snap of 1 is a steady return")
	var spring := Abilities.from_dict(STEADY)
	spring.tongue_settle = 1.0
	var fast_start := 1.0 - TongueMotion.remaining(0.35, spring)
	var slow_end := TongueMotion.remaining(0.85, spring) - TongueMotion.remaining(1.0, spring)
	_check(fast_start > 0.5 and slow_end < 0.05, "the spring return is more than half done in the first 35%% and eases in (%.2f done at 35%%, %.3f left at 85%%)" % [fast_start, slow_end])


## The steady lash against the lash PR #67 had, tick for tick.
func _steady_is_the_old_lash(tongue: Node, player: Player, room: Room) -> void:
	for facing in [1, -1]:
		var run := _lash(tongue, player, STEADY, facing)
		var xs: Array = run["xs"]
		var peak := _peak(xs)
		var index := xs.find(peak)
		var expected: Array = _old_lash(peak)
		var same := xs.size() == expected.size()
		for k in mini(xs.size(), expected.size()):
			same = same and absf(float(xs[k]) - float(expected[k])) < 0.0001
		_check(same, "the steady values go out and come back tick for tick as the old lash did (facing %d, %.1f px, %d ticks)" % [facing, peak, xs.size()])
		_check(index == int(ceil(peak / (220.0 * DT) - 0.0001)) - 1, "and take %d ticks out" % (index + 1))
	_check(_damage(room) == 1, "the left lash hit the wall once")


## One set of values, in play. `values` goes on top of the starting ones.
func _in_play(name: String, values: Dictionary, tongue: Node, player: Player, room: Room) -> void:
	var all := Abilities.new().to_dict()
	all.merge(values, true)
	var peak_speed: float = all["tongue_speed"] * all["tongue_strike"]
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
	for k in range(peak_at + 1, xs.size()):
		back_ok = back_ok and float(xs[k]) <= float(xs[k - 1]) + 1e-9
		legs.append(float(xs[k - 1]) - float(xs[k]))
	_check(out_ok and back_ok, "%s: the way out never goes back and the way in never goes forward" % name)
	var jump := 0.0
	for k in range(1, xs.size()):
		jump = maxf(jump, absf(float(xs[k]) - float(xs[k - 1])))
	_check(jump <= maxf(peak_speed * DT, 50.0) + 1e-6, "%s: no tick moves the tip more than it can (%.1f px)" % [name, jump])
	# The creep is slower than the snap.
	if all["tongue_creep"] > 0.0:
		var first := float(xs[0])
		var fastest := 0.0
		for k in range(1, peak_at + 1):
			fastest = maxf(fastest, float(xs[k]) - float(xs[k - 1]))
		_check(first < fastest * 0.5, "%s: the creep (%.2f px a tick) is slower than the snap (%.2f px a tick)" % [name, first, fastest])
	# A spring return is fastest early and eases in.
	if all["tongue_settle"] >= 1.0:
		var top := 0
		for k in legs.size():
			if float(legs[k]) > float(legs[top]):
				top = k
		_check(top <= legs.size() / 2 and float(legs[legs.size() - 1]) < float(legs[top]), "%s: the return is quickest early (tick %d of %d) and slower at the end" % [name, top + 1, legs.size()])
	_check(tongue.cooldown_left > 0.0, "%s: the cooldown starts when the tongue is home" % name)

	# A hit on the wall to the left, 30 px away.
	var before := _damage(room)
	var hit := _lash(tongue, player, values, -1)
	xs = hit["xs"]
	phases = hit["phases"]
	var out_ticks := 0
	var stuck := 0
	for p in phases:
		if p == tongue.Phase.OUT:
			out_ticks += 1
		elif p == tongue.Phase.STICK:
			stuck += 1
	_check(_damage(room) == before + 1, "%s: one lash hits the wall once" % name)
	_check(_peak(xs) < 40.0 and _peak(xs) > 25.0, "%s: and the tip stops at the wall (%.1f px)" % [name, _peak(xs)])
	_check(out_ticks <= 9, "%s: a wall 30 px away is hit in %d ticks, no more than the 9 the steady lash took" % [name, out_ticks])
	var wanted := int(ceil(all["tongue_stick"] / DT - 0.0001)) if all["tongue_stick"] > 0.0 else 0
	_check(stuck == wanted, "%s: it sticks to the wall for %d ticks (%d)" % [name, wanted, stuck])
	if stuck > 0:
		var held := true
		for k in xs.size():
			if phases[k] == tongue.Phase.STICK:
				held = held and is_equal_approx(float(xs[k]), _peak(xs))
		_check(held, "%s: and the tip holds where it hit" % name)
	var body := player.get_node("Visual") as PlayerBody
	var pad := body.pad_rect(_peak(xs))
	var line := body.tongue_rect(_peak(xs))
	_check(pad.size == Vector2(2, 3) and pad.position == pad.position.round() and pad.get_center().y == line.get_center().y and pad.position.x == line.position.x, "%s: the pad is a whole-pixel 2 x 3 box centred on the line at the tip" % name)
	_check(not tongue.retracting and not tongue.active, "%s: and the tongue is home" % name)
	_check(room.wall_at(Rect2(room.position + Grid.cell_to_world(Vector2i(20, 32)) + Vector2(2, 2), Vector2(2, 2))) != null, "%s: and the wall still stands (strength 99)" % name)


## The tip stays on the wall when the player moves under it.
func _stick_follows(tongue: Node, player: Player, world: Node) -> void:
	_apply({})
	_stand(world, player)
	player.facing = -1
	tongue.cooldown_left = 0.0
	tongue.lash()
	var guard := 0
	while tongue.phase != tongue.Phase.STICK and tongue.active and guard < 100:
		tongue._move(DT)
		guard += 1
	_check(tongue.phase == tongue.Phase.STICK, "the tongue sticks to the wall")
	var tip_x: float = tongue.tip().x
	var out: float = tongue.extension
	player.global_position.x -= 2.0
	tongue._move(DT)
	_check(is_equal_approx(tongue.tip().x, tip_x) and is_equal_approx(tongue.extension, out - 2.0), "the player stepping 2 px toward the wall shortens the tongue and leaves the tip where it hit")
	tongue.end()
	tongue.cooldown_left = 0.0
	_stand(world, player)


## A lash made with the player pressed to the wall hits at once: no creep, no stick.
func _at_once(tongue: Node, player: Player, world: Node) -> void:
	var room: Room = world.current
	var reach := _peak(_lash(tongue, player, {}, -1)["xs"])
	_stand(world, player)
	_apply({})
	player.facing = -1
	var before := _damage(room)
	tongue.cooldown_left = 0.0
	player.global_position.x -= reach
	var lashed: bool = tongue.lash()
	_check(lashed and _damage(room) == before + 1 and tongue.phase == tongue.Phase.BACK and tongue.extension == 0.0, "pressed to the wall, a lash hits at once, with no creep, no stick and nothing to wait out")
	tongue._move(DT)
	_check(not tongue.active, "and is over on the next tick")
	tongue.cooldown_left = 0.0
	_stand(world, player)


## A tongue this fast would skip a thin wall if it went in one step.
func _no_skipping(tongue: Node, player: Player, room: Room) -> void:
	var values := {"tongue_speed": 2000.0, "tongue_strike": 10.0}
	var before := _damage(room)
	var run := _lash(tongue, player, values, -1)
	_check(_damage(room) == before + 1 and _peak(run["xs"]) < 40.0, "at 2000 px/s times 10 the tip still stops at the wall (%.1f px) and hits it once" % _peak(run["xs"]))
	_check(not tongue.active, "and the lash ends")


## A longer tongue does not delay a close hit.
func _length_does_not_delay(tongue: Node, player: Player) -> void:
	for pair in [["Frog", {}], ["Steady", STEADY]]:
		var values: Dictionary = pair[1]
		var short := _lash(tongue, player, values, -1)
		var long_values := values.duplicate()
		long_values["tongue_length"] = 100.0
		var long := _lash(tongue, player, long_values, -1)
		var short_out := _ticks_out(short)
		var long_out := _ticks_out(long)
		_check(short_out == long_out and short["xs"].size() == long["xs"].size(), "%s: a 100 px tongue hits the wall 30 px away as soon as a 50 px one (%d ticks, %d)" % [pair[0], long_out, short_out])


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
