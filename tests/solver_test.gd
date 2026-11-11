extends TestCase

## The solver, on worlds built from strings. A room behind a pit of spikes too
## wide to jump is open only to a player who has found double jump, and the
## validator says which pickup it needs. (Imprint, which used to be the key
## here, is a legacy dev-tools feature the solver does not model.)

## Nine upgrades that each raise a different stat, so each one counts.
const NINE: Array[String] = ["tongue_speed", "tongue_snap", "tongue_length", "tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick"]

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	var ok := true
	ok = _double_jump() and ok
	ok = _lash() and ok
	ok = _climb() and ok
	ok = _ceiling() and ok
	ok = _progression() and ok
	ok = _many_rounds() and ok
	ok = _locks() and ok
	ok = _saved_lock() and ok
	ok = _machines() and ok
	ok = _one_way() and ok
	ok = _tall_fall() and ok
	finish("SOLVER", ok)


## The air jump: a pit of 10 cells is crossable with one and not without, a pit
## of 24 is not, and a pickup that gives double jump opens the way and is what
## room 2 needs.
func _double_jump() -> bool:
	var ok := true
	var narrow := {}
	var rooms := _world(narrow)
	var abilities := Abilities.new()
	abilities.air_jumps = 1
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = check(open.errors.is_empty(), "with an air jump a 10-cell pit is crossed %s" % [open.errors]) and ok
	var plain := ReachGraph.new(rooms, _cfg, Abilities.new()).analyze("1")
	ok = check(_has(plain.errors, "Room 2 cannot be reached"), "and without one it is not") and ok

	var wide := {}
	for x in range(4, 28):
		wide[Vector2i(x, 16)] = "^"
	var too_wide := ReachGraph.new(_world(wide), _cfg, abilities).analyze("1")
	ok = check(_has(too_wide.errors, "Room 2 cannot be reached"), "a pit of 24 cells is too wide even for an air jump %s" % [too_wide.errors]) and ok

	narrow[Vector2i(4, 16)] = "U"
	rooms = _world(narrow, "legend:\n  U = pickup id=key upgrade=double_jump value=1\n---\n")
	var base := Abilities.new()
	var report := ReachGraph.new(rooms, _cfg, base).solve("1")
	ok = check(report.errors.is_empty() and report.needs.get("2") == ["key"] and base.air_jumps == 0, "a pickup that gives double jump opens room 2, which needs it (%s)" % [report.needs.get("2")]) and ok

	# A cached run gives the same answer as one without a cache, air edges included.
	var directory := "user://air_cache_test"
	var cache := SolverCache.new(directory)
	var warm_graph := ReachGraph.new(_world(narrow), _cfg, abilities)
	warm_graph.cache = cache
	var cold := warm_graph.analyze("1")
	cache.save()
	var again_cache := SolverCache.new(directory)
	var again := ReachGraph.new(_world(narrow), _cfg, abilities)
	again.cache = again_cache
	var warm := again.analyze("1")
	ok = check(cold.errors == warm.errors and again_cache.stats["air_rooms_cached"] > 0 and again_cache.stats["air_rooms_solved"] == 0, "the air edges come back from the cache (%s)" % [again_cache.stats]) and ok
	for id in ["1", "2"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join("%s.json" % id))
	return ok


## Tongue Lash: a pickup in a box whose left wall is breakable is out of reach until
## the player has Tongue Lash, and then it is taken from the ledge in front of the
## wall. The wall is a state of one visit, so room 1 is still the same room
## in the report. A line of fire blocked by solid keeps it shut, a box with no
## wall to lash is shut, and the cap on states is an error.
func _lash() -> bool:
	var ok := true
	var header := "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n  B = breakable id=wall\n---\n"
	var marks := {}
	for x in range(9, 21):
		marks[Vector2i(x, 16)] = "."
	# A box four cells tall (a jump clears it) whose left wall is breakable.
	for x in range(22, 27):
		marks[Vector2i(x, 13)] = "#"
	for y in range(13, 17):
		marks[Vector2i(26, y)] = "#"
	for y in range(14, 17):
		marks[Vector2i(22, y)] = "B"
	marks[Vector2i(24, 16)] = "U"
	var rooms := _world(marks, header)
	var without := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = check(_has(without.errors, "pickup gem"), "without Tongue Lash, a pickup behind a breakable wall is out of reach %s" % [without.errors]) and ok
	var armed := Abilities.new()
	armed.tongue_unlocked = true
	var graph := ReachGraph.new(rooms, _cfg, armed)
	var with_lash := graph.analyze("1")
	ok = check(with_lash.errors.is_empty(), "with Tongue Lash it is taken %s" % [with_lash.errors]) and ok
	ok = check(with_lash.pickups.any(func(p: ReachGraph.PickupReport) -> bool: return p.id == "gem" and p.reached), "and the report lists it as reached") and ok
	ok = check(with_lash.reached_ledges == with_lash.total_ledges, "the ledge inside the box counts as reached, and no state counts as a place of its own (%d of %d)" % [with_lash.reached_ledges, with_lash.total_ledges]) and ok

	# A progression: Tongue Lash is a pickup on the near side, and the pickup needs it.
	var chain := _world(marks.merged({Vector2i(4, 16): "G"}), "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n  B = breakable id=wall\n  G = pickup id=lashpick upgrade=tongue_lash\n---\n")
	var report := ReachGraph.new(chain, _cfg).solve("1")
	ok = check(report.errors.is_empty() and report.needs.get("pickup|gem") == ["lashpick"], "a pickup that gives Tongue Lash is what the one behind the wall needs (%s %s)" % [report.errors, report.needs.get("pickup|gem")]) and ok

	# Solid in the line of fire keeps the wall out of reach, even with Tongue Lash.
	var blocked := marks.duplicate()
	for y in range(6, 17):
		blocked[Vector2i(18, y)] = "#"
	var shut := ReachGraph.new(_world(blocked, header), _cfg, armed).analyze("1")
	ok = check(_has(shut.errors, "pickup gem"), "a solid between the player and the wall keeps it shut %s" % [shut.errors]) and ok

	# Without a wall to shoot, the box is shut.
	var sealed := marks.duplicate()
	for y in range(14, 17):
		sealed[Vector2i(22, y)] = "#"
	var solid := ReachGraph.new(_world(sealed, "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n---\n"), _cfg, armed).analyze("1")
	ok = check(_has(solid.errors, "pickup gem"), "a box of plain solid stays shut with Tongue Lash") and ok

	# The copy of the room with the wall broken is cached under its own key.
	var directory := "user://lash_cache_test"
	var cache := SolverCache.new(directory)
	var cold_graph := ReachGraph.new(rooms, _cfg, armed)
	cold_graph.cache = cache
	var cold := cold_graph.analyze("1")
	cache.save()
	var again_cache := SolverCache.new(directory)
	var again := ReachGraph.new(rooms, _cfg, armed)
	again.cache = again_cache
	var warm := again.analyze("1")
	ok = check(cold.errors == warm.errors and warm.errors.is_empty() and again_cache.stats["edge_rooms_solved"] == 0 and again_cache.stats["edge_rooms_cached"] >= 3, "the states come back from the cache, each room's file apart (%s)" % [again_cache.stats]) and ok
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join(file))
	return ok


## Tongue Climb: a pillar whose top is 13 cells above the floor, past the 10 a
## double jump rises, so its pickup is out of reach until the player can hang on
## the pillar's face and hop up it. Only with the power-up (and the lash it is
## built on), and a pickup that gives it is what the pillar's needs.
func _climb() -> bool:
	var ok := true
	var header := "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n---\n"
	var marks := {}
	for x in range(22, 27):
		for y in range(4, 17):
			marks[Vector2i(x, y)] = "#"
	marks[Vector2i(24, 3)] = "U"
	var rooms := _world(marks, header)
	var armed := Abilities.new()
	armed.air_jumps = 1
	armed.tongue_unlocked = true
	var plain := ReachGraph.new(rooms, _cfg, armed).analyze("1")
	ok = check(_has(plain.errors, "pickup gem"), "a pillar 13 cells high is out of reach of a double jump %s" % [plain.errors]) and ok
	armed.tongue_climb = true
	var climbing := ReachGraph.new(rooms, _cfg, armed).analyze("1")
	ok = check(climbing.errors.is_empty(), "with Tongue Climb its top is reached %s" % [climbing.errors]) and ok
	ok = check(climbing.pickups.any(func(p: ReachGraph.PickupReport) -> bool: return p.id == "gem" and p.reached), "and the report lists the pickup as reached") and ok
	var no_lash := Abilities.new()
	no_lash.air_jumps = 1
	no_lash.tongue_climb = true
	var shut := ReachGraph.new(rooms, _cfg, no_lash).analyze("1")
	ok = check(_has(shut.errors, "pickup gem"), "the climb is built on the lash: without Tongue Lash it does nothing %s" % [shut.errors]) and ok

	# What each hang reaches comes back from the cache.
	var directory := "user://climb_cache_test"
	var cache := SolverCache.new(directory)
	var cold_graph := ReachGraph.new(rooms, _cfg, armed)
	cold_graph.cache = cache
	var cold := cold_graph.analyze("1")
	cache.save()
	var again_cache := SolverCache.new(directory)
	var again := ReachGraph.new(rooms, _cfg, armed)
	again.cache = again_cache
	var warm := again.analyze("1")
	ok = check(cold.errors == warm.errors and warm.errors.is_empty() and cache.stats["climb_hangs_solved"] > 0 and again_cache.stats["climb_hangs_solved"] == 0 and again_cache.stats["climb_hangs_cached"] > 0, "the hangs come back from the cache (%s then %s)" % [cache.stats, again_cache.stats]) and ok
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join(file))

	# The power-up as a pickup on the near side: the pillar's pickup needs it.
	var chain := _world(marks.merged({Vector2i(4, 16): "G"}), "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n  G = pickup id=climbpick upgrade=tongue_climb\n---\n")
	var base := Abilities.new()
	base.air_jumps = 1
	base.tongue_unlocked = true
	var report := ReachGraph.new(chain, _cfg, base).solve("1")
	ok = check(report.errors.is_empty() and report.needs.get("pickup|gem") == ["climbpick"], "a pickup that gives Tongue Climb is what the pillar's pickup needs (%s %s)" % [report.errors, report.needs.get("pickup|gem")]) and ok
	return ok


## Ceiling hangs: a spiked floor 22 cells wide under a low ceiling, too wide to
## jump and with no wall to climb across it. Hanging from the ceiling, letting go,
## using the spare jump and lashing up again crosses it to the pickup; with
## `climb_ceiling` off, or without Tongue Climb, it stays out of reach.
func _ceiling() -> bool:
	var ok := true
	var header := "legend:\n  U = pickup id=gem upgrade=tongue_cooldown value=0.5\n---\n"
	var marks := {}
	for x in range(5, 28):
		for y in range(1, 10):
			marks[Vector2i(x, y)] = "#"
	for x in range(6, 28):
		marks[Vector2i(x, 16)] = "^"
	marks[Vector2i(29, 16)] = "U"
	var rooms := _world(marks, header)
	var armed := Abilities.new()
	armed.tongue_unlocked = true
	armed.tongue_climb = true
	var hanging := ReachGraph.new(rooms, _cfg, armed).analyze("1")
	ok = check(hanging.pickups.any(func(p: ReachGraph.PickupReport) -> bool: return p.id == "gem" and p.reached), "hanging from the ceiling, hang to hang, crosses the spikes to the pickup %s" % [hanging.errors]) and ok
	armed.climb_ceiling = false
	var walls_only := ReachGraph.new(rooms, _cfg, armed).analyze("1")
	ok = check(_has(walls_only.errors, "pickup gem"), "with ceilings off it is out of reach %s" % [walls_only.errors]) and ok
	var no_climb := Abilities.new()
	no_climb.tongue_unlocked = true
	var plain := ReachGraph.new(rooms, _cfg, no_climb).analyze("1")
	ok = check(_has(plain.errors, "pickup gem"), "and so it is without Tongue Climb %s" % [plain.errors]) and ok
	return ok


func _progression() -> bool:
	var ok := true
	# The pickup that gives double jump is on the near side.
	var rooms := _world({Vector2i(4, 16): "U"}, "legend:\n  U = pickup id=key upgrade=double_jump value=1\n---\n")
	var base := Abilities.new()
	var graph := ReachGraph.new(rooms, _cfg, base)
	var report := graph.solve("1")
	ok = check(report.errors.is_empty(), "taking the pickup opens the way %s" % [report.errors]) and ok
	ok = check(report.needs.get("1") == [], "room 1 needs nothing (%s)" % [report.needs.get("1")]) and ok
	ok = check(report.needs.get("2") == ["key"], "room 2 needs the pickup that gives double jump (%s)" % [report.needs.get("2")]) and ok
	ok = check(base.air_jumps == 0 and graph.abilities.air_jumps == 0, "and solving leaves the starting abilities alone") and ok

	# A reward on the far side needs double jump too, and says so.
	rooms = _world({Vector2i(4, 16): "U", Vector2i(26, 16): "V"}, "legend:\n  U = pickup id=key upgrade=double_jump value=1\n  V = pickup id=wide upgrade=tongue_cooldown value=0.5\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = check(report.errors.is_empty() and report.needs.get("pickup|wide") == ["key"] and not report.needs.has("pickup|key"), "a pickup across the pit needs the double jump pickup, which needs nothing (%s)" % [report.needs]) and ok

	# The same pickup on the far side can never be taken.
	rooms = _world({Vector2i(26, 16): "U"}, "legend:\n  U = pickup id=key upgrade=double_jump value=1\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = check(_has(report.errors, "Room 2 cannot be reached") and _has(report.errors, "pickup key"), "a pickup behind its own gate is an error %s" % [report.errors]) and ok
	return ok


## Nine ability-changing pickups in sequence need more rounds than the old
## fixed limit allowed. Reachability is scripted so this tests the progression
## loop and real upgrade application without nine expensive solves.
func _many_rounds() -> bool:
	var glyphs := "ABCDEFGHIJ"
	var spots: Array[Vector2i] = [
		Vector2i(3, 16), Vector2i(4, 16), Vector2i(5, 16),
		Vector2i(6, 16), Vector2i(7, 16), Vector2i(8, 16),
		Vector2i(21, 16), Vector2i(22, 16), Vector2i(23, 16),
		Vector2i(24, 16),
	]
	var marks := {}
	var legend: Array[String] = ["legend:"]
	var chain: Array[String] = []
	for i in 9:
		var glyph := glyphs.substr(i, 1)
		var id := "effect_%d" % (i + 1)
		marks[spots[i]] = glyph
		legend.append("  %s = pickup id=%s upgrade=%s value=1000" % [glyph, id, NINE[i]])
		chain.append(id)
	var goal_glyph := glyphs.substr(9, 1)
	marks[spots[9]] = goal_glyph
	legend.append("  %s = pickup id=goal upgrade=%s value=1000" % [goal_glyph, NINE[8]])
	legend.append("---")
	chain.append("goal")

	var base := Abilities.new()
	var graph := ChainReachGraph.new(_world(marks, "\n".join(legend) + "\n"), _cfg, base, chain)
	var report := graph.solve("1")
	var goal_reached := false
	for pickup in report.pickups:
		if pickup.id == "goal":
			goal_reached = pickup.reached
	var expected: Array[String] = []
	expected.assign(chain.slice(0, 9))
	var ok := true
	ok = check(report.errors.is_empty(), "a progression chain longer than eight rounds has no errors %s" % [report.errors]) and ok
	ok = check(goal_reached, "the pickup after nine sequential upgrades is reached") and ok
	ok = check(report.needs.get("pickup|goal") == expected, "the final pickup needs all nine earlier upgrades (%s)" % [report.needs.get("pickup|goal")]) and ok
	ok = check(base.to_dict() == Abilities.new().to_dict() and graph.abilities.to_dict() == Abilities.new().to_dict(), "the long solve leaves the starting abilities alone") and ok
	return ok


## `exits: saved`: the doors of a save room wait for its machine, which is
## touched like a pickup but gives nothing.
func _saved_lock() -> bool:
	var ok := true
	var legend := "exits: saved\nlegend:\n  S = save id=s2_save\n---\n"
	var door_right := {Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	var door_left := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}
	var first := {Vector2i(2, 16): "P"}
	first.merge(door_right)
	var third := door_left

	# The machine stands on the floor of the second room, which has a third behind it.
	var second := {Vector2i(10, 16): "S"}
	second.merge(door_left)
	second.merge(door_right)
	var rooms := _rooms([[first, ""], [second, legend], [third, ""]], false, ["1", "s2", "3"])
	var things := ReachGraph.new(rooms, _cfg).geometry_of(rooms["s2"]).things
	ok = check(things.size() == 1 and things[0].size == Vector2(50, 30), "the solver touches a save machine over its whole 50 x 30 zone, as the game does (%s)" % [things]) and ok
	var report := ReachGraph.new(rooms, _cfg).solve("1")
	ok = check(report.errors.is_empty() and report.reached_rooms.has("3"), "a save room whose machine is on its floor lets the player through %s" % [report.errors]) and ok
	ok = check(report.pickups.any(func(p: ReachGraph.PickupReport) -> bool: return p.id == "s2_save" and p.type == "save" and p.reached), "and the machine is listed as reached") and ok
	ok = check(report.needs.get("3") == [], "taking it gives nothing, so the room behind needs nothing (%s)" % [report.needs.get("3")]) and ok

	# The machine on a platform nobody can jump up to: the doors stay shut.
	second = {Vector2i(10, 8): "S", Vector2i(8, 9): "#", Vector2i(9, 9): "#", Vector2i(10, 9): "#", Vector2i(11, 9): "#", Vector2i(12, 9): "#"}
	second.merge(door_left)
	second.merge(door_right)
	rooms = _rooms([[first, ""], [second, legend], [third, ""]], false, ["1", "s2", "3"])
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = check(_has(report.errors, "Room 3 cannot be reached") and _has(report.errors, "save s2_save"), "a machine that cannot be reached shuts the way on, and is named %s" % [report.errors]) and ok
	return ok


## Exit rules: a room that holds its doors shut until its token is taken is
## reachable when the token is, and a dead end when it is not.
func _locks() -> bool:
	var ok := true
	var legend := "exits: pickups\nlegend:\n  T = token id=t1\n---\n"
	var door_right := {Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	var door_left := {Vector2i(0, 15): "X", Vector2i(0, 16): "X"}

	# The token is on the floor of the second room, which has a third room behind it.
	var first := {Vector2i(2, 16): "P"}
	first.merge(door_right)
	var second := {Vector2i(10, 16): "T"}
	second.merge(door_left)
	second.merge(door_right)
	var third := door_left
	var rooms := _rooms([[first, ""], [second, legend], [third, ""]])
	var report := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = check(report.errors.is_empty(), "a locked room whose token is on its floor lets the player through %s" % [report.errors]) and ok
	ok = check(report.reached_rooms.has("3"), "and the room behind it is reached") and ok

	# The same token seven cells up in the air: nobody gets it, nobody gets out.
	second = {Vector2i(10, 8): "T"}
	second.merge(door_left)
	second.merge(door_right)
	rooms = _rooms([[first, ""], [second, legend], [third, ""]])
	report = ReachGraph.new(rooms, _cfg).analyze("1")
	ok = check(_has(report.errors, "Room 3 cannot be reached"), "a locked room whose token cannot be reached shuts the way on %s" % [report.errors]) and ok
	ok = check(_has(report.errors, "token t1"), "and says which token %s" % [report.errors]) and ok
	ok = check(not report.traps.is_empty(), "and its floor is a trap, since the player came in and cannot leave") and ok
	return ok


## Three tokens and a 3TM that gives double jump, on the near side of the pit. The
## machine only pays out once all three are taken.
func _machines() -> bool:
	var ok := true
	var legend := "legend:\n  A = token id=t1\n  B = token id=t2\n  C = token id=t3\n  M = machine id=m upgrade=double_jump value=1\n---\n"
	var marks := {Vector2i(3, 16): "A", Vector2i(4, 16): "B", Vector2i(4, 13): "C", Vector2i(6, 16): "M"}
	var report := ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = check(report.errors.is_empty(), "three tokens and a 3TM give double jump, which opens the pit %s" % [report.errors]) and ok
	ok = check(report.needs.get("2") == ["m", "t1", "t2", "t3"], "room 2 needs all three tokens and the machine (%s)" % [report.needs.get("2")]) and ok
	ok = check(report.needs.get("1") == [], "room 1 needs nothing (%s)" % [report.needs.get("1")]) and ok

	marks.erase(Vector2i(4, 13))
	legend = "legend:\n  A = token id=t1\n  B = token id=t2\n  M = machine id=m upgrade=double_jump value=1\n---\n"
	report = ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = check(_has(report.errors, "Room 2 cannot be reached"), "two tokens are not enough, and the room stays shut %s" % [report.errors]) and ok

	# A 3TM nobody can touch is reported like any other thing out of reach.
	marks = {Vector2i(3, 16): "A", Vector2i(4, 16): "B", Vector2i(4, 13): "C", Vector2i(6, 6): "M"}
	legend = "legend:\n  A = token id=t1\n  B = token id=t2\n  C = token id=t3\n  M = machine id=m upgrade=double_jump value=1\n---\n"
	report = ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = check(_has(report.errors, "machine m"), "a 3TM up where nobody can touch it is an error %s" % [report.errors]) and ok
	return ok


## A room you fall into and cannot climb out of is a trap, unless the room says
## `trap: allowed`, and then it is only a warning.
func _one_way() -> bool:
	var ok := true
	var hole := {Vector2i(2, 16): "P"}
	var ceiling := {}
	for x in range(6, 13):
		hole[Vector2i(x, 17)] = "X"
		ceiling[Vector2i(x, 0)] = "X"
	var report := ReachGraph.new(_rooms([[hole, ""], [ceiling, ""]], true), _cfg).analyze("1")
	ok = check(_has(report.errors, "trap") and not report.traps.is_empty(), "a room you drop into and cannot leave is a trap %s" % [report.errors]) and ok
	report = ReachGraph.new(_rooms([[hole, ""], [ceiling, "trap: allowed\n---\n"]], true), _cfg).analyze("1")
	ok = check(report.errors.is_empty() and report.traps.is_empty(), "with trap: allowed it is not an error %s" % [report.errors]) and ok
	ok = check(_has(report.warnings, "one-way") and report.one_way.size() == 1, "but it is a warning (%s)" % [report.warnings]) and ok
	ok = check(_has(report.warnings, "cannot be reached from inside"), "and its own door, which nobody inside can touch, is a warning too (%s)" % [report.warnings]) and ok
	return ok


## A room four screens tall: the body that falls through the door above lands on
## its floor, however far down that is.
func _tall_fall() -> bool:
	var ok := true
	var hole := {Vector2i(2, 16): "P"}
	for x in range(6, 13):
		hole[Vector2i(x, 17)] = "X"
	var entries: Array = [
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": _room(hole)},
		{"id": "2", "grid_pos": Vector2i(0, 1), "text": "trap: allowed\n---\n" + _tall(72)},
	]
	var errors: Array[String] = []
	var built := RoomParser.build(entries, "1", errors)
	ok = check(errors.is_empty(), "a room four screens tall loads %s" % [errors]) and ok
	var report := ReachGraph.new(built["rooms"], _cfg).analyze("1")
	ok = check(report.errors.is_empty() and report.reached_rooms.has("2"), "a fall of 70 cells lands on the floor %s" % [report.errors]) and ok
	return ok


## One screen wide and `rows` tall, a floor and walls, and a door in the ceiling
## at columns 2 to 9 and 6 to 12.
func _tall(rows: int) -> String:
	var lines: Array[String] = []
	for y in rows:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == rows - 1
			var door := y == 0 and x >= 6 and x <= 12
			row += "X" if door else ("#" if edge else ".")
		lines.append(row)
	return "\n".join(lines) + "\n"


## Rooms from the left, one screen each, or from the top when `vertical`, built
## from [marks, header] pairs.
func _rooms(parts: Array, vertical := false, ids := []) -> Dictionary:
	var entries: Array = []
	for i in parts.size():
		entries.append({"id": String(ids[i]) if i < ids.size() else str(i + 1), "grid_pos": Vector2i(0, i) if vertical else Vector2i(i, 0), "text": String(parts[i][1]) + _room(parts[i][0])})
	var errors: Array[String] = []
	var built := RoomParser.build(entries, "1", errors)
	if not errors.is_empty():
		print("  world did not load: ", errors)
	return built["rooms"]


## Two rooms side by side. Room 1 is a floor with a pit of spikes 10 cells wide
## in it, a start on the left, and a door on the far side that leads to room 2.
func _world(marks: Dictionary, header := "") -> Dictionary:
	var first := {Vector2i(2, 16): "P", Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	for x in range(9, 19):
		first[Vector2i(x, 16)] = "^"
	first.merge(marks, true)
	var errors: Array[String] = []
	var built := RoomParser.build([
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": header + _room(first)},
		{"id": "2", "grid_pos": Vector2i(1, 0), "text": _room({Vector2i(0, 15): "X", Vector2i(0, 16): "X"})},
	], "1", errors)
	if not errors.is_empty():
		print("  world did not load: ", errors)
	return built["rooms"]


func _room(marks: Dictionary) -> String:
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += marks.get(Vector2i(x, y), "#" if edge else ".")
		rows.append(row)
	return "\n".join(rows) + "\n"


func _has(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	return false


## A cheap progression fixture: each exact ability prefix reveals the next
## real pickup. `solve` and `_with` remain the production implementations.
class ChainReachGraph extends ReachGraph:
	var chain: Array[String] = []

	func _init(rooms: Dictionary, movement: MovementConfig, ability_set: Abilities, ids: Array[String]) -> void:
		chain.assign(ids)
		super._init(rooms, movement, ability_set)

	func _analyze(_start_room: String) -> Report:
		var report := Report.new()
		var empty := Abilities.new()
		var reached_count := 0
		for i in chain.size():
			if abilities.to_dict() == _with(empty, chain.slice(0, i)).to_dict():
				reached_count = i + 1
				break
		var reached_ids := {}
		for i in reached_count:
			reached_ids[chain[i]] = true
		for id in _things:
			var def: EntityDef = _things[id]
			var found := ReachGraph.PickupReport.new()
			found.id = id
			found.type = def.type
			found.room = "1"
			found.upgrade = String(def.props.get("upgrade", ""))
			found.value = String(def.props.get("value", ""))
			found.reached = reached_ids.has(id)
			report.pickups.append(found)
		return report
