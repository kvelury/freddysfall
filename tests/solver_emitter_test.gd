extends TestCase

## The solver's view of emitters (tests/emitter_test.gd covers the room format,
## the platforms' lives and play). Optional: it is run by `tools/check.sh --solver`.


func _initialize() -> void:
	watchdog(120.0)
	var ok := true
	ok = _solver() and ok
	ok = _lash_up_solver() and ok
	finish("SOLVER EMITTER", ok)


func _solver() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	# A ledge 7 cells above the floor, and an emitted platform 3 cells up that
	# carries a rider within a jump of it.
	var rows := {
		10: "#" + ".".repeat(18) + "#".repeat(12) + "#",
		14: "#EEEE" + "-".repeat(12) + "^" + ".".repeat(13) + "#",
	}
	var rooms := _world_of(rows, "  E = emitter id=e1 speed=40 every=2\n")
	var graph := ReachGraph.new(rooms, cfg)
	var report := graph.analyze("1")
	var high: ReachGraph.Ledge = null
	var ride: ReachGraph.Ledge = null
	for ledge in graph.ledges_in("1"):
		if ledge.row == 9 and not ledge.moving:
			high = ledge
		if ledge.moving:
			ride = ledge
	ok = check(ride != null and report.reached.has(ride), "an emitted platform is reached from the floor") and ok
	ok = check(high != null and report.reached.has(high), "and the high ledge is reached by riding it") and ok
	var plain := {10: rows[10]}
	graph = ReachGraph.new(_world_of(plain, ""), cfg)
	report = graph.analyze("1")
	var reached_high := false
	for ledge in graph.ledges_in("1"):
		if ledge.row == 9 and report.reached.has(ledge):
			reached_high = true
	ok = check(not reached_high, "without the emitter the high ledge is out of reach") and ok
	return ok


## A rider lashes up through a breakable wall in a ceiling to reach the ledge
## on top of it. Without Tongue Lash it is out of reach, and so it is with the
## emitter gone (nothing else puts the player under the hole).
func _lash_up_solver() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var rows := {
		10: "#" + "#".repeat(8) + "BB" + "#".repeat(21),
		14: "#EEEE" + "-".repeat(12) + "^" + ".".repeat(13) + "#",
	}
	var legend := "  E = emitter id=e1 speed=40 every=2\n  B = breakable id=roof\n"
	# The top ledge, in the room as loaded or in a copy of it with the roof broken.
	var top_reached := func(graph: ReachGraph, report: ReachGraph.Report) -> bool:
		for key in graph._ledges:
			for ledge: ReachGraph.Ledge in graph._ledges[key]:
				if ledge.row == 9 and not ledge.moving and report.reached.has(ledge):
					return true
		return false
	var graph := ReachGraph.new(_world_of(rows, legend), cfg)
	var report := graph.analyze("1")
	ok = check(not top_reached.call(graph, report), "without Tongue Lash the ledge on top of the ceiling is out of reach") and ok
	var armed := Abilities.new()
	armed.tongue_unlocked = true
	graph = ReachGraph.new(_world_of(rows, legend), cfg, armed)
	report = graph.analyze("1")
	ok = check(top_reached.call(graph, report), "with it, a rider lashing up through the roof reaches it") and ok
	# The same roof with nothing to ride: the floor is too far under it.
	var no_ride := {10: rows[10]}
	graph = ReachGraph.new(_world_of(no_ride, "  B = breakable id=roof\n"), cfg, armed)
	report = graph.analyze("1")
	ok = check(not top_reached.call(graph, report), "and without the emitter's platform to ride, it is not") and ok
	# A solid slab, not a wall, in the way of the lash.
	var solid_roof := {10: "#".repeat(32), 14: rows[14]}
	graph = ReachGraph.new(_world_of(solid_roof, "  E = emitter id=e1 speed=40 every=2\n"), cfg, armed)
	report = graph.analyze("1")
	ok = check(not top_reached.call(graph, report), "a solid ceiling is not lashed through") and ok
	return ok


## A 32 x 18 room from a few rows (y -> text); the rest is empty air in a box.
static func _world_of(rows: Dictionary, legend: String) -> Dictionary:
	var out: Array[String] = []
	for y in 18:
		if rows.has(y):
			out.append(rows[y])
		elif y == 0 or y == 17:
			out.append("#".repeat(32))
		elif y == 16:
			out.append("#" + ".".repeat(28) + "P" + ".#")
		else:
			out.append("#" + ".".repeat(30) + "#")
	var errors: Array[String] = []
	var text := "legend:\n" + legend + "---\n" + "\n".join(out)
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": text}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
	return built["rooms"]
