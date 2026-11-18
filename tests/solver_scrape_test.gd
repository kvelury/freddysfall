extends TestCase

## The solver's view of scraping platforms: the platform is one ledge per
## stretch of its rider row, so the far side of an unbroken wall is not reached
## by riding, and it is once the wall is broken. (tests/scrape_test.gd covers the
## format and play.) Optional: it is run by `tools/check.sh --solver`.


func _initialize() -> void:
	watchdog(120.0)
	finish("SOLVER SCRAPE", _solver())


func _solver() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	# Start ledge on the left, a scraping ferry, a breakable column standing in
	# its rider row, and the only other ledge past the column. Spikes below.
	var rows := {
		Vector2i(0, 12): "####LLLL------------------.#####",
		Vector2i(0, 16): "#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#",
	}
	for y in range(1, 12):
		rows[Vector2i(0, y)] = "#.........BB...................#"
	var legend := "  L = platform id=ferry speed=60 pause=0.3 scrape=true\n  B = breakable id=col\n"
	var rooms := _rooms(rows, legend, Vector2i(1, 11))
	var info: RoomInfo = rooms["1"]
	var segments := ReachGraph.band_segments(info, info.platforms[0])
	ok = check(segments == [Vector2(40, 100), Vector2(120, 260)], "the rider row splits into the stretches either side of the column %s" % [segments]) and ok

	var plain := ReachGraph.new(rooms, cfg)
	var report := plain.analyze("1")
	var parts: Array[ReachGraph.Ledge] = []
	var far: ReachGraph.Ledge = null
	for ledge in plain.ledges_in("1"):
		if ledge.moving:
			parts.append(ledge)
		elif ledge.row == 11 and ledge.x0 >= 27:
			far = ledge
	ok = check(parts.size() == 2 and parts[0].segmented and parts[1].segmented, "the ferry is two ledges, one per stretch (%d)" % parts.size()) and ok
	ok = check(parts.size() == 2 and report.reached.has(parts[0]) and not report.reached.has(parts[1]), "without the tongue only the near stretch is reached") and ok
	ok = check(far != null and not report.reached.has(far), "and the ledge past the column is not reached by riding through it") and ok
	ok = check(parts.size() == 2 and parts[1].describe().contains("cells 12-25"), "a stretch names its cells: %s" % [parts[1].describe() if parts.size() == 2 else ""]) and ok

	var abilities := Abilities.new()
	abilities.tongue_unlocked = true
	var lash := ReachGraph.new(rooms, cfg, abilities)
	report = lash.analyze("1")
	far = null
	for ledge in lash.ledges_in("1"):
		if not ledge.moving and ledge.row == 11 and ledge.x0 >= 27:
			far = ledge
	var broken_far := false
	for ledge: ReachGraph.Ledge in report.reached:
		if ledge.room_id != "1" and not ledge.moving and ledge.row == 11 and ledge.x0 >= 27:
			broken_far = true
	ok = check(broken_far, "with Tongue Lash the column is lashed from the start ledge and the far ledge is reached in the room with it broken") and ok
	ok = check(report.errors.is_empty() or report.errors.all(func(e: String) -> bool: return not e.contains("cannot be reached from room")), "and the room solves %s" % [report.errors]) and ok
	return ok


func _rooms(rows: Dictionary, legend: String, spawn: Vector2i) -> Dictionary:
	var errors: Array[String] = []
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": "trap: allowed\nlegend:\n" + legend + "---\n" + _room(rows, spawn)}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
	return built["rooms"]


## A walled one-screen room. `rows` maps Vector2i(0, y) to a whole row.
func _room(rows: Dictionary, spawn: Vector2i) -> String:
	var out: Array[String] = []
	for y in 18:
		var row := ""
		if rows.has(Vector2i(0, y)):
			row = rows[Vector2i(0, y)]
		else:
			for x in 32:
				row += "#" if x == 0 or y == 0 or x == 31 or y == 17 else "."
		if y == spawn.y and spawn.x >= 0:
			row = row.substr(0, spawn.x) + "P" + row.substr(spawn.x + 1)
		out.append(row)
	return "\n".join(out) + "\n"


func _has(lines: Array, fragment: String) -> bool:
	for line in lines:
		if String(line).contains(fragment):
			return true
	print("  nothing containing '%s' in %s" % [fragment, lines])
	return false
