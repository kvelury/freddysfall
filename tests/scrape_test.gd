extends TestCase

## Platforms that scrape (`scrape=true`): a side-to-side platform whose rider
## row may hold solid or breakable walls. The format: what the parser accepts
## and refuses. Play: a rider carried into such a wall is stopped by it, never
## crushed, and drops once the platform has slid out from under them; with the
## wall gone the rider is carried straight on. The solver: the platform is one
## ledge per stretch of its rider row, so the far side of an unbroken wall is
## not reached by riding, and it is once the wall is broken.

const DT := 1.0 / 60.0
const SCRAPE := "  L = platform id=p1 speed=60 pause=0 scrape=true\n"


func _initialize() -> void:
	watchdog(120.0)
	var ok := true
	ok = _parser() and ok
	ok = _carry() and ok
	ok = _solver() and ok
	finish("SCRAPE", ok)


# --- the room format -------------------------------------------------------


func _parser() -> bool:
	var ok := true
	var track := "#.....LLLLL--------------------#"
	var wall_over := "#...............#..............#"
	var info := _load({Vector2i(0, 13): wall_over, Vector2i(0, 14): track}, SCRAPE)
	ok = check(info != null and info.platforms.size() == 1 and info.platforms[0].scrape, "scrape=true lets a solid stand in the rider row") and ok
	var errors := _errors({Vector2i(0, 13): wall_over, Vector2i(0, 14): track}, "  L = platform id=p1 speed=60\n")
	ok = check(_has(errors, "needs open air in the row above"), "without scrape the same wall is still an error") and ok
	var wall_rows := {Vector2i(0, 14): track}
	for y in range(1, 14):
		wall_rows[Vector2i(0, y)] = "#...............B..............#"
	info = _load(wall_rows, SCRAPE + "  B = breakable id=w1\n")
	ok = check(info != null and info.breakables.has("w1"), "a breakable wall may reach down into the rider row") and ok
	errors = _errors(wall_rows, "  L = platform id=p1 speed=60\n  B = breakable id=w1\n")
	ok = check(_has(errors, "breakable wall w1 is in the way"), "but only with scrape") and ok
	errors = _errors({Vector2i(0, 13): "#.........T.....#..............#", Vector2i(0, 14): track}, SCRAPE + "  T = token id=t1\n")
	ok = check(_has(errors, "token t1 is in the way of moving platform p1"), "a thing in the rider row is still an error") and ok
	errors = _errors({Vector2i(0, 13): "#...............^..............#", Vector2i(0, 14): track}, SCRAPE)
	ok = check(_has(errors, "scrape=true allows only solid and breakable walls there"), "spikes in the rider row are still an error") and ok
	errors = _errors({Vector2i(0, 14): track}, SCRAPE)
	ok = check(_has(errors, "nothing stands in its rider row"), "scrape=true with an open rider row is an error") and ok
	errors = _errors({Vector2i(0, 13): wall_over, Vector2i(0, 14): track}, "  L = platform id=p1 speed=60 scrape=yes\n")
	ok = check(_has(errors, "scrape= is true"), "scrape= takes only true") and ok
	var up := {Vector2i(0, 9): "#.........#....................#", Vector2i(0, 15): "#.........LLL..................#"}
	for y in range(10, 15):
		up[Vector2i(0, y)] = "#.........|||..................#"
	errors = _errors(up, SCRAPE)
	ok = check(_has(errors, "scrape is for platforms that go side to side"), "scrape on a platform that goes up and down is an error") and ok
	return ok


# --- play ------------------------------------------------------------------


## A rider on a platform sliding right toward a wall cell in its rider row.
func _carry() -> bool:
	var ok := true
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	for speed in [30.0, 60.0, 150.0]:
		for way in [1, -1]:
			var result := _ride(cfg, speed, way, true)
			var face := 150.0 - MovementSim.HALF.x if way > 0 else 160.0 + MovementSim.HALF.x
			ok = check(not result["crushed"], "at %d px/s going %s a rider carried into the wall is never crushed" % [speed, "right" if way > 0 else "left"]) and ok
			ok = check(absf(float(result["stopped_at"]) - face) < 0.01, "  it is held at the wall's face (%.2f, face %.2f)" % [result["stopped_at"], face]) and ok
			ok = check(result["fell"], "  and drops once the platform has slid out from under it") and ok
			var clear := _ride(cfg, speed, way, false)
			ok = check(not clear["crushed"] and clear["passed"], "  with the wall gone it is carried straight past") and ok
	return ok


## Rides a platform four cells wide on row 16 that slides `way` (1 right, -1
## left) at `speed`, with a body on it and, if `wall`, the cell (15, 15) solid.
func _ride(cfg: MovementConfig, speed: float, way: int, wall: bool) -> Dictionary:
	var rects: Array[Rect2] = []
	if wall:
		rects.append(Rect2(150, 150, 10, 10))
	var start := Rect2i(4, 16, 4, 1) if way > 0 else Rect2i(24, 16, 4, 1)
	var movers := Movers.new([PlatformPath.new("p", start, Vector2i(way, 0), 20, speed, 0.0)])
	var s := MovementSim.State.new()
	s.position = Vector2(float(start.position.x) * 10.0 + 20.0, 155.0)
	s.grounded = true
	s.riding = 0
	var out := {"crushed": false, "stopped_at": NAN, "fell": false, "passed": false}
	var ticks := ceili(200.0 / speed * 60.0) + 60
	for tick in ticks:
		MovementSim.step(cfg, s, rects, 0.0, false, false, DT, movers, tick)
		out["crushed"] = bool(out["crushed"]) or s.crushed
		if s.position.y > 156.0:
			out["fell"] = true
			break
		out["stopped_at"] = s.position.x
		if (way > 0 and s.position.x > 165.0) or (way < 0 and s.position.x < 145.0):
			out["passed"] = true
	return out


# --- the solver ------------------------------------------------------------


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


# --- helpers ---------------------------------------------------------------


func _load(rows: Dictionary, legend: String) -> RoomInfo:
	var errors: Array[String] = []
	var built := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": "legend:\n" + legend + "---\n" + _room(rows, Vector2i(2, 16))}], "1", errors)
	if not errors.is_empty():
		print("  room did not load: ", errors)
		return null
	return built["rooms"]["1"]


func _errors(rows: Dictionary, legend: String) -> Array[String]:
	var errors: Array[String] = []
	RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": "legend:\n" + legend + "---\n" + _room(rows, Vector2i(2, 16))}], "1", errors)
	return errors


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
