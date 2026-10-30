extends SceneTree

## The solver with Imprint. A room behind a pit of spikes too wide to jump is
## open only to a player who has found Imprint, and the validator says which
## pickup it needs. Worlds are built from strings.

var _cfg: MovementConfig


func _initialize() -> void:
	_cfg = load("res://src/player/movement.tres")
	var ok := true
	ok = _gate() and ok
	ok = _double_jump() and ok
	ok = _lash() and ok
	ok = _progression() and ok
	ok = _many_rounds() and ok
	ok = _forbidden() and ok
	ok = _locks() and ok
	ok = _saved_lock() and ok
	ok = _machines() and ok
	ok = _one_way() and ok
	ok = _tall_fall() and ok
	ok = _barrier() and ok
	ok = _not_last_block() and ok
	ok = _second_simulation() and ok
	ok = _room_six() and ok
	ok = _from_a_mover() and ok
	print("IMPRINTSOLVER %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _gate() -> bool:
	var ok := true
	var rooms := _world({})
	var locked := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = _check(_has(locked.errors, "Room 2 cannot be reached"), "without Imprint the room past the pit is out of reach %s" % [locked.errors]) and ok

	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var started := Time.get_ticks_msec()
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	ok = _check(open.errors.is_empty(), "with Imprint it is reachable, using a platform over the spikes %s" % [open.errors]) and ok
	ok = _check(seconds < 10.0, "and the search is fast enough (%.1f s)" % seconds) and ok

	# A platform that breaks too soon is no use: each jump has to fit in its life.
	abilities.imprint_duration = 1.0
	var brief := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(_has(brief.errors, "Room 2 cannot be reached"), "a platform that lasts one second is not enough to cross %s" % [brief.errors]) and ok

	# So short that it is gone before a jump can land on it: nothing to search.
	abilities.imprint_duration = 0.5
	var gone := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(_has(gone.errors, "Room 2 cannot be reached"), "a platform gone before a jump lands on it crosses nothing %s" % [gone.errors]) and ok

	# The starting duration is the one that has to be enough.
	ok = _check(is_equal_approx(Abilities.new().imprint_duration, 1.5), "the starting duration is 1.5 seconds, which crossed the pit above") and ok
	return ok


## The air jump: a pit of 10 cells is crossable with one and not without, a pit
## of 24 is not, and a pickup that gives double jump opens the way and is what
## room 2 needs.
func _double_jump() -> bool:
	var ok := true
	var narrow := {Vector2i(19, 16): ".", Vector2i(20, 16): "."}
	var rooms := _world(narrow)
	var abilities := Abilities.new()
	abilities.air_jumps = 1
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(open.errors.is_empty(), "with an air jump a 10-cell pit is crossed %s" % [open.errors]) and ok
	var plain := ReachGraph.new(rooms, _cfg, Abilities.new()).analyze("1")
	ok = _check(_has(plain.errors, "Room 2 cannot be reached"), "and without one it is not") and ok

	var wide := {}
	for x in range(4, 28):
		wide[Vector2i(x, 16)] = "^"
	var too_wide := ReachGraph.new(_world(wide), _cfg, abilities).analyze("1")
	ok = _check(_has(too_wide.errors, "Room 2 cannot be reached"), "a pit of 24 cells is too wide even for an air jump %s" % [too_wide.errors]) and ok

	narrow[Vector2i(4, 16)] = "U"
	rooms = _world(narrow, "legend:\n  U = pickup id=key upgrade=double_jump value=1\n---\n")
	var base := Abilities.new()
	var report := ReachGraph.new(rooms, _cfg, base).solve("1")
	ok = _check(report.errors.is_empty() and report.needs.get("2") == ["key"] and base.air_jumps == 0, "a pickup that gives double jump opens room 2, which needs it (%s)" % [report.needs.get("2")]) and ok

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
	ok = _check(cold.errors == warm.errors and again_cache.stats["air_rooms_cached"] > 0 and again_cache.stats["air_rooms_solved"] == 0, "the air edges come back from the cache (%s)" % [again_cache.stats]) and ok
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
	var header := "legend:\n  U = pickup id=gem upgrade=imprint_width value=3\n  B = breakable id=wall\n---\n"
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
	ok = _check(_has(without.errors, "pickup gem"), "without Tongue Lash, a pickup behind a breakable wall is out of reach %s" % [without.errors]) and ok
	var armed := Abilities.new()
	armed.tongue_unlocked = true
	var graph := ReachGraph.new(rooms, _cfg, armed)
	var with_lash := graph.analyze("1")
	ok = _check(with_lash.errors.is_empty(), "with Tongue Lash it is taken %s" % [with_lash.errors]) and ok
	ok = _check(with_lash.pickups.any(func(p: Dictionary) -> bool: return p["id"] == "gem" and p["reached"]), "and the report lists it as reached") and ok
	ok = _check(with_lash.reached_ledges == with_lash.total_ledges, "the ledge inside the box counts as reached, and no state counts as a place of its own (%d of %d)" % [with_lash.reached_ledges, with_lash.total_ledges]) and ok

	# A progression: Tongue Lash is a pickup on the near side, and the pickup needs it.
	var chain := _world(marks.merged({Vector2i(4, 16): "G"}), "legend:\n  U = pickup id=gem upgrade=imprint_width value=3\n  B = breakable id=wall\n  G = pickup id=lashpick upgrade=tongue_lash\n---\n")
	var report := ReachGraph.new(chain, _cfg).solve("1")
	ok = _check(report.errors.is_empty() and report.needs.get("pickup|gem") == ["lashpick"], "a pickup that gives Tongue Lash is what the one behind the wall needs (%s %s)" % [report.errors, report.needs.get("pickup|gem")]) and ok

	# Solid in the line of fire keeps the wall out of reach, even with Tongue Lash.
	var blocked := marks.duplicate()
	for y in range(6, 17):
		blocked[Vector2i(18, y)] = "#"
	var shut := ReachGraph.new(_world(blocked, header), _cfg, armed).analyze("1")
	ok = _check(_has(shut.errors, "pickup gem"), "a solid between the player and the wall keeps it shut %s" % [shut.errors]) and ok

	# Without a wall to shoot, the box is shut.
	var sealed := marks.duplicate()
	for y in range(14, 17):
		sealed[Vector2i(22, y)] = "#"
	var solid := ReachGraph.new(_world(sealed, "legend:\n  U = pickup id=gem upgrade=imprint_width value=3\n---\n"), _cfg, armed).analyze("1")
	ok = _check(_has(solid.errors, "pickup gem"), "a box of plain solid stays shut with Tongue Lash") and ok

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
	ok = _check(cold.errors == warm.errors and warm.errors.is_empty() and again_cache.stats["edge_rooms_solved"] == 0 and again_cache.stats["edge_rooms_cached"] >= 3, "the states come back from the cache, each room's file apart (%s)" % [again_cache.stats]) and ok
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join(file))
	return ok


func _progression() -> bool:
	var ok := true
	# The pickup that gives Imprint is on the near side.
	var rooms := _world({Vector2i(4, 16): "U"}, "legend:\n  U = pickup id=key upgrade=imprint\n---\n")
	var base := Abilities.new()
	var graph := ReachGraph.new(rooms, _cfg, base)
	var report := graph.solve("1")
	ok = _check(report.errors.is_empty(), "taking the pickup opens the way %s" % [report.errors]) and ok
	ok = _check(report.needs.get("1") == [], "room 1 needs nothing (%s)" % [report.needs.get("1")]) and ok
	ok = _check(report.needs.get("2") == ["key"], "room 2 needs the pickup that gives Imprint (%s)" % [report.needs.get("2")]) and ok
	ok = _check(not base.imprint_unlocked and not graph.abilities.imprint_unlocked, "and solving leaves the starting abilities alone") and ok

	# A reward on the far side needs Imprint too, and says so.
	rooms = _world({Vector2i(4, 16): "U", Vector2i(26, 16): "V"}, "legend:\n  U = pickup id=key upgrade=imprint\n  V = pickup id=wide upgrade=imprint_width value=3\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(report.errors.is_empty() and report.needs.get("pickup|wide") == ["key"] and not report.needs.has("pickup|key"), "a pickup across the pit needs the Imprint pickup, which needs nothing (%s)" % [report.needs]) and ok

	# The same pickup on the far side can never be taken.
	rooms = _world({Vector2i(26, 16): "U"}, "legend:\n  U = pickup id=key upgrade=imprint\n---\n")
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(_has(report.errors, "Room 2 cannot be reached") and _has(report.errors, "pickup key"), "a pickup behind its own gate is an error %s" % [report.errors]) and ok
	return ok


## Nine ability-changing pickups in sequence need more rounds than the old
## fixed limit allowed. Reachability is scripted so this tests the progression
## loop and real upgrade application without nine expensive Imprint searches.
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
		var effect := "step_%d" % (i + 1)
		marks[spots[i]] = glyph
		legend.append("  %s = pickup id=%s upgrade=imprint_effect value=%s" % [glyph, id, effect])
		chain.append(id)
	var goal_glyph := glyphs.substr(9, 1)
	marks[spots[9]] = goal_glyph
	legend.append("  %s = pickup id=goal upgrade=imprint_effect value=step_9" % goal_glyph)
	legend.append("---")
	chain.append("goal")

	var base := Abilities.new()
	var graph := ChainReachGraph.new(_world(marks, "\n".join(legend) + "\n"), _cfg, base, chain)
	var report := graph.solve("1")
	var goal_reached := false
	for pickup in report.pickups:
		if pickup["id"] == "goal":
			goal_reached = pickup["reached"]
	var expected: Array[String] = []
	expected.assign(chain.slice(0, 9))
	var ok := true
	ok = _check(report.errors.is_empty(), "a progression chain longer than eight rounds has no errors %s" % [report.errors]) and ok
	ok = _check(goal_reached, "the pickup after nine sequential upgrades is reached") and ok
	ok = _check(report.needs.get("pickup|goal") == expected, "the final pickup needs all nine earlier upgrades (%s)" % [report.needs.get("pickup|goal")]) and ok
	ok = _check(base.imprint_effects.is_empty() and graph.abilities.imprint_effects.is_empty(), "the long solve leaves the starting abilities alone") and ok
	return ok


func _forbidden() -> bool:
	var ok := true
	# ~ cells over the whole pit leave no place for a platform.
	var marks := {}
	for y in range(8, 17):
		for x in range(9, 21):
			if y != 16:
				marks[Vector2i(x, y)] = "~"
	var rooms := _world(marks)
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var report := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(_has(report.errors, "Room 2 cannot be reached"), "~ cells over the pit forbid the platform, and the room stays shut %s" % [report.errors]) and ok
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
	ok = _check(things.size() == 1 and things[0].size == Vector2(50, 30), "the solver touches a save machine over its whole 50 x 30 zone, as the game does (%s)" % [things]) and ok
	var report := ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(report.errors.is_empty() and report.reached_rooms.has("3"), "a save room whose machine is on its floor lets the player through %s" % [report.errors]) and ok
	ok = _check(report.pickups.any(func(p: Dictionary) -> bool: return p["id"] == "s2_save" and p["type"] == "save" and p["reached"]), "and the machine is listed as reached") and ok
	ok = _check(report.needs.get("3") == [], "taking it gives nothing, so the room behind needs nothing (%s)" % [report.needs.get("3")]) and ok

	# The machine on a platform nobody can jump up to: the doors stay shut.
	second = {Vector2i(10, 8): "S", Vector2i(8, 9): "#", Vector2i(9, 9): "#", Vector2i(10, 9): "#", Vector2i(11, 9): "#", Vector2i(12, 9): "#"}
	second.merge(door_left)
	second.merge(door_right)
	rooms = _rooms([[first, ""], [second, legend], [third, ""]], false, ["1", "s2", "3"])
	report = ReachGraph.new(rooms, _cfg).solve("1")
	ok = _check(_has(report.errors, "Room 3 cannot be reached") and _has(report.errors, "save s2_save"), "a machine that cannot be reached shuts the way on, and is named %s" % [report.errors]) and ok
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
	ok = _check(report.errors.is_empty(), "a locked room whose token is on its floor lets the player through %s" % [report.errors]) and ok
	ok = _check(report.reached_rooms.has("3"), "and the room behind it is reached") and ok

	# The same token seven cells up in the air: nobody gets it, nobody gets out.
	second = {Vector2i(10, 8): "T"}
	second.merge(door_left)
	second.merge(door_right)
	rooms = _rooms([[first, ""], [second, legend], [third, ""]])
	report = ReachGraph.new(rooms, _cfg).analyze("1")
	ok = _check(_has(report.errors, "Room 3 cannot be reached"), "a locked room whose token cannot be reached shuts the way on %s" % [report.errors]) and ok
	ok = _check(_has(report.errors, "token t1"), "and says which token %s" % [report.errors]) and ok
	ok = _check(not report.traps.is_empty(), "and its floor is a trap, since the player came in and cannot leave") and ok
	return ok


## Three tokens and a 3TM that gives Imprint, on the near side of the pit. The
## machine only pays out once all three are taken.
func _machines() -> bool:
	var ok := true
	var legend := "legend:\n  A = token id=t1\n  B = token id=t2\n  C = token id=t3\n  M = machine id=m upgrade=imprint\n---\n"
	var marks := {Vector2i(3, 16): "A", Vector2i(4, 16): "B", Vector2i(4, 13): "C", Vector2i(6, 16): "M"}
	var report := ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = _check(report.errors.is_empty(), "three tokens and a 3TM give Imprint, which opens the pit %s" % [report.errors]) and ok
	ok = _check(report.needs.get("2") == ["m", "t1", "t2", "t3"], "room 2 needs all three tokens and the machine (%s)" % [report.needs.get("2")]) and ok
	ok = _check(report.needs.get("1") == [], "room 1 needs nothing (%s)" % [report.needs.get("1")]) and ok

	marks.erase(Vector2i(4, 13))
	legend = "legend:\n  A = token id=t1\n  B = token id=t2\n  M = machine id=m upgrade=imprint\n---\n"
	report = ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = _check(_has(report.errors, "Room 2 cannot be reached"), "two tokens are not enough, and the room stays shut %s" % [report.errors]) and ok

	# A 3TM nobody can touch is reported like any other thing out of reach.
	marks = {Vector2i(3, 16): "A", Vector2i(4, 16): "B", Vector2i(4, 13): "C", Vector2i(6, 6): "M"}
	legend = "legend:\n  A = token id=t1\n  B = token id=t2\n  C = token id=t3\n  M = machine id=m upgrade=imprint\n---\n"
	report = ReachGraph.new(_world(marks, legend), _cfg).solve("1")
	ok = _check(_has(report.errors, "machine m"), "a 3TM up where nobody can touch it is an error %s" % [report.errors]) and ok
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
	ok = _check(_has(report.errors, "trap") and not report.traps.is_empty(), "a room you drop into and cannot leave is a trap %s" % [report.errors]) and ok
	report = ReachGraph.new(_rooms([[hole, ""], [ceiling, "trap: allowed\n---\n"]], true), _cfg).analyze("1")
	ok = _check(report.errors.is_empty() and report.traps.is_empty(), "with trap: allowed it is not an error %s" % [report.errors]) and ok
	ok = _check(_has(report.warnings, "one-way") and report.one_way.size() == 1, "but it is a warning (%s)" % [report.warnings]) and ok
	ok = _check(_has(report.warnings, "cannot be reached from inside"), "and its own door, which nobody inside can touch, is a warning too (%s)" % [report.warnings]) and ok
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
	ok = _check(errors.is_empty(), "a room four screens tall loads %s" % [errors]) and ok
	var report := ReachGraph.new(built["rooms"], _cfg).analyze("1")
	ok = _check(report.errors.is_empty() and report.reached_rooms.has("2"), "a fall of 70 cells lands on the floor %s" % [report.errors]) and ok
	return ok


## Room 6's shape: a hole in the floor that a wall and a roof cover on the side
## the player comes from. The wall is six cells tall, more than a jump, so only
## an Imprint platform gets the player over it.
func _barrier() -> bool:
	var ok := true
	var marks := {Vector2i(28, 16): "P"}
	for x in range(6, 11):
		marks[Vector2i(x, 11)] = "#"
	for y in range(12, 17):
		marks[Vector2i(10, y)] = "#"
	var ceiling := {}
	for x in range(2, 10):
		marks[Vector2i(x, 17)] = "X"
		ceiling[Vector2i(x, 0)] = "X"
	var rooms := _rooms([[marks, ""], [ceiling, "trap: allowed\n---\n"]], true)
	var shut := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = _check(_has(shut.errors, "Room 2 cannot be reached"), "a wall six cells tall keeps the player from the hole %s" % [shut.errors]) and ok
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(open.errors.is_empty(), "and an Imprint platform gets them over %s" % [open.errors]) and ok

	# At four cells the wall is a plain jump.
	for y in range(11, 13):
		for x in range(6, 11):
			marks.erase(Vector2i(x, y)) if y == 11 else null
	marks.clear()
	marks[Vector2i(28, 16)] = "P"
	for x in range(6, 11):
		marks[Vector2i(x, 13)] = "#"
	for y in range(14, 17):
		marks[Vector2i(10, y)] = "#"
	for x in range(2, 10):
		marks[Vector2i(x, 17)] = "X"
	var low := ReachGraph.new(_rooms([[marks, ""], [ceiling, "trap: allowed\n---\n"]], true), _cfg).analyze("1")
	ok = _check(low.errors.is_empty(), "a wall four cells tall is just a jump %s" % [low.errors]) and ok
	return ok


## The solver counts only the block that lasts as footing, and which block that
## is depends on where the player stood to place it: the jump's start. A jump
## that comes down on any other block is not counted, even though the block is
## there when it lands, because it goes first. A platform of one, whose only
## block is the last, counts the same landing. Found by looking, on a plain floor.
func _not_last_block() -> bool:
	var ok := true
	var fixture := _floor_fixture(3)
	var search: ImprintSearch = fixture["search"]
	var narrow: Dictionary = _floor_fixture(1)
	var limit := 80
	var found: ImprintSearch.Candidate = null
	var block := Vector2i.ZERO
	for row in range(16, 11, -1):
		for column in range(2, 28):
			var cell := Vector2i(column, row)
			var full: Array[Rect2] = fixture["near"].duplicate()
			full.append(Grid.cell_rect(Rect2i(cell, Vector2i(3, 1))))
			for arc: ImprintSearch.Arc in search._arcs_of(fixture["ledge"], fixture["info"], fixture["geo"]):
				var lasts: Array[Vector2i] = search._last_cells(cell, 3, arc.start.x)
				if lasts.size() != 1:
					continue
				var last := Grid.cell_rect(Rect2i(lasts[0], Vector2i(1, 1)))
				var on_last: Vector2 = search._landing(fixture["geo"], arc, full, last, limit)
				if on_last.x == on_last.x:
					continue
				for k in 3:
					var other := Vector2i(column + k, row)
					if other == lasts[0]:
						continue
					var rect := Grid.cell_rect(Rect2i(other, Vector2i(1, 1)))
					var on_full: Vector2 = search._landing(fixture["geo"], arc, full, rect, limit)
					var alone: Array[Rect2] = fixture["near"].duplicate()
					alone.append(rect)
					var on_alone: Vector2 = search._landing(fixture["geo"], arc, alone, rect, limit)
					if on_full.x == on_full.x and on_alone.x == on_alone.x and on_full.distance_to(on_alone) < 0.5:
						found = ImprintSearch.Candidate.new()
						found.cell = cell
						found.arcs.append(arc)
						block = other
						break
				if found != null:
					break
			if found != null:
				break
		if found != null:
			break
	ok = _check(found != null, "a jump that lands only on a block that goes before the last one exists") and ok
	ok = _check(found != null and not search._lands_on(fixture["info"], fixture["geo"], fixture["ledge"], found, limit), "and with a platform of three it is not counted") and ok
	if found != null:
		var one := ImprintSearch.Candidate.new()
		one.cell = block
		one.arcs = found.arcs
		var narrow_search: ImprintSearch = narrow["search"]
		ok = _check(narrow_search._lands_on(narrow["info"], narrow["geo"], narrow["ledge"], one, limit) and one.last == block, "while a platform of one on that block counts it") and ok

	# Which block lasts, from where the player stands: the nearest, or either of two on a tie.
	ok = _check(search._last_cells(Vector2i(10, 12), 3, 50.0) == [Vector2i(10, 12)], "a player to the left: the left block lasts") and ok
	ok = _check(search._last_cells(Vector2i(10, 12), 3, 300.0) == [Vector2i(12, 12)], "a player to the right: the right block lasts") and ok
	ok = _check(search._last_cells(Vector2i(10, 12), 3, 115.0) == [Vector2i(11, 12)], "a player under the middle: the middle lasts") and ok
	ok = _check(search._last_cells(Vector2i(10, 12), 2, 110.0) == [Vector2i(11, 12), Vector2i(10, 12)], "on a tie either block may last, as the player may face either way (%s)" % [search._last_cells(Vector2i(10, 12), 2, 110.0)]) and ok
	return ok


## A plain floor with the start on the left, and the solver parts for a platform
## of `width`: the graph, the search, the room, its geometry, the start ledge and
## the solids near it.
func _floor_fixture(width: int) -> Dictionary:
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	abilities.imprint_width = width
	var rooms := _rooms([[{Vector2i(3, 16): "P"}, ""]])
	var graph := ReachGraph.new(rooms, _cfg, abilities)
	var info := graph.room_info("1")
	var geo := graph.geometry_of(info)
	var ledge: ReachGraph.Ledge = graph.ledges_in("1")[0]
	return {"graph": graph, "search": ImprintSearch.new(graph), "info": info, "geo": geo, "ledge": ledge, "near": graph.near_solids(geo.rects, ledge)}


## A jump that lands on the last block only because the platform's other blocks
## are there (it brushes one, and is carried onto the last) is no use once they
## have gone. `_lands_on` runs the jump again with the last block alone and
## drops it. Found by looking: on a plain floor, a platform of three, the jumps
## from the start ledge that land on the last block with the whole platform
## there, and where they land with the last block alone.
func _second_simulation() -> bool:
	var ok := true
	var fixture := _floor_fixture(3)
	var search: ImprintSearch = fixture["search"]
	var info: RoomInfo = fixture["info"]
	var geo: ReachGraph.Geometry = fixture["geo"]
	var ledge: ReachGraph.Ledge = fixture["ledge"]
	var near: Array[Rect2] = fixture["near"]
	var limit := 80
	var carried: ImprintSearch.Candidate = null
	var steady: ImprintSearch.Candidate = null
	for row in range(16, 11, -1):
		for column in range(2, 28):
			var cell := Vector2i(column, row)
			var full: Array[Rect2] = near.duplicate()
			full.append(Grid.cell_rect(Rect2i(cell, Vector2i(3, 1))))
			for arc: ImprintSearch.Arc in search._arcs_of(ledge, info, geo):
				if carried != null and steady != null:
					break
				var lasts: Array[Vector2i] = search._last_cells(cell, 3, arc.start.x)
				if lasts.size() != 1:
					continue
				var last := Grid.cell_rect(Rect2i(lasts[0], Vector2i(1, 1)))
				var with_all: Vector2 = search._landing(geo, arc, full, last, limit)
				if with_all.x != with_all.x:
					continue
				var alone: Array[Rect2] = near.duplicate()
				alone.append(last)
				var by_itself: Vector2 = search._landing(geo, arc, alone, last, limit)
				var made := ImprintSearch.Candidate.new()
				made.cell = cell
				made.arcs.append(arc)
				if by_itself.x != by_itself.x and carried == null:
					carried = made
				elif by_itself.x == by_itself.x and with_all.distance_to(by_itself) < 0.5 and steady == null:
					steady = made
			if carried != null and steady != null:
				break
		if carried != null and steady != null:
			break
	ok = _check(carried != null, "a jump that lands on the last block only because of the others exists") and ok
	ok = _check(carried != null and not search._lands_on(info, geo, ledge, carried, limit), "and it is not counted") and ok
	ok = _check(steady != null and search._lands_on(info, geo, ledge, steady, limit), "while a jump that lands the same with the last block alone is") and ok
	return ok


## The real room 6 and room 7, lifted out of the world: without Imprint the
## wall keeps the player from the hole, and with it they get over.
func _room_six() -> bool:
	var ok := true
	var six := FileAccess.get_file_as_string("res://data/rooms/6.txt").split("\n")
	# Row 16 of the grid, below the header (a `trap:` line and a divider) if there is one.
	var top := six.find("---") + 1
	six[top + 16] = six[top + 16].substr(0, 28) + "P" + six[top + 16].substr(29)
	var seven := FileAccess.get_file_as_string("res://data/rooms/7.txt")
	var errors: Array[String] = []
	var built := RoomParser.build([
		{"id": "6", "grid_pos": Vector2i(0, 0), "text": "\n".join(six)},
		{"id": "7", "grid_pos": Vector2i(0, 1), "text": seven},
	], "6", errors)
	ok = _check(errors.is_empty(), "room 6 and 7 load on their own %s" % [errors]) and ok
	var shut := ReachGraph.new(built["rooms"], _cfg).analyze("6")
	ok = _check(_has(shut.errors, "Room 7 cannot be reached"), "room 6's wall keeps the player from the hole without Imprint %s" % [shut.errors]) and ok
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var open := ReachGraph.new(built["rooms"], _cfg, abilities).analyze("6")
	ok = _check(open.errors.size() == 1 and open.reached_rooms.has("7"), "and with Imprint they drop into room 7 %s" % [open.errors]) and ok
	# Without room 11 beyond exit 2, nothing in room 7 gets up to its health
	# pip, with a platform 2 or 3 wide: it is reached only by the drop.
	ok = _check(_has(open.errors, "health r7_health"), "room 7's pip is out of reach from below with a 2-wide Imprint %s" % [open.errors]) and ok
	abilities.imprint_width = 3
	var wide := ReachGraph.new(built["rooms"], _cfg, abilities).analyze("6")
	ok = _check(_has(wide.errors, "health r7_health"), "and with a 3-wide one %s" % [wide.errors]) and ok
	return ok


## A rider can put an Imprint down. Room 1's floor ends at spikes; a platform
## slides right over them, and a door is high in the far wall, eight rows above
## the rider: out of a jump, and out of reach from the floor even with Imprint.
## Only a platform placed while riding gets there.
func _from_a_mover() -> bool:
	var ok := true
	var marks := {Vector2i(2, 16): "P"}
	for x in range(5, 31):
		marks[Vector2i(x, 16)] = "^"
	for x in range(5, 10):
		marks[Vector2i(x, 13)] = "L"
	for x in range(10, 21):
		marks[Vector2i(x, 13)] = "-"
	for x in range(24, 31):
		marks[Vector2i(x, 5)] = "#"
	for y in range(2, 5):
		marks[Vector2i(31, y)] = "X"
	var errors: Array[String] = []
	var rooms: Dictionary = RoomParser.build([
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": "legend:\n  L = platform id=t_lift speed=60\n---\n" + _room(marks)},
		{"id": "2", "grid_pos": Vector2i(1, 0), "text": _room({Vector2i(0, 2): "X", Vector2i(0, 3): "X", Vector2i(0, 4): "X", Vector2i(1, 5): "#", Vector2i(2, 5): "#"})},
	], "1", errors)["rooms"]
	ok = _check(errors.is_empty(), "the moving-platform world loads %s" % [errors]) and ok
	var plain := ReachGraph.new(rooms, _cfg).analyze("1")
	ok = _check(_has(plain.errors, "Room 2 cannot be reached"), "without Imprint the high door is out of reach %s" % [plain.errors]) and ok
	var abilities := Abilities.new()
	abilities.imprint_unlocked = true
	var open := ReachGraph.new(rooms, _cfg, abilities).analyze("1")
	ok = _check(not _has(open.errors, "Room 2 cannot be reached"), "a platform put down while riding reaches it %s" % [open.errors]) and ok
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


## Two rooms side by side. Room 1 is a floor with a pit of spikes 12 cells wide
## in it, a start on the left, and a door on the far side that leads to room 2.
func _world(marks: Dictionary, header := "") -> Dictionary:
	var first := {Vector2i(2, 16): "P", Vector2i(31, 15): "X", Vector2i(31, 16): "X"}
	for x in range(9, 21):
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


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond


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
			report.pickups.append({
				"id": id,
				"type": def.type,
				"room": "1",
				"upgrade": String(def.props.get("upgrade", "")),
				"value": String(def.props.get("value", "")),
				"reached": reached_ids.has(id),
			})
		return report
