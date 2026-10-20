extends SceneTree

## Loads the whole world, then checks it can be played: every room and door
## reachable from the start, and no place you cannot get back from.
## Exits non-zero on any error. Warnings (ledges nobody reached) do not fail.
## tools/validate.sh runs this.


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var problems: Array[String] = []
	problems.append_array(Upgrades.problems())
	problems.append_array(data.errors)
	for message in problems:
		print("FAIL ", message)
	if not problems.is_empty():
		print("validate fail: %d problems loading %d rooms" % [problems.size(), data.rooms.size()])
		quit(1)
		return

	var started := Time.get_ticks_msec()
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var report := ReachGraph.new(data.rooms, cfg).solve(data.start_room)
	for message in report.errors:
		print("FAIL ", message)
	for message in report.warnings:
		print("warn ", message)
	for pickup in report.pickups:
		var gives: String = (pickup["upgrade"] + " " + pickup["value"]).strip_edges()
		print("%s %s in room %s%s%s" % [pickup["type"], pickup["id"], pickup["room"], ": " + gives if not gives.is_empty() else "", "" if pickup["reached"] else "  (not reached)"])
	var ids: Array = data.rooms.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for id in ids:
		if not report.needs.has(id):
			print("room %s is not reached" % id)
		else:
			var needs: Array = report.needs[id]
			print("room %s needs %s" % [id, "nothing" if needs.is_empty() else ", ".join(needs)])
	var kinds := {}
	for pickup in report.pickups:
		kinds[pickup["id"]] = pickup["type"]
	var extra: Array = report.needs.keys().filter(func(k: String) -> bool: return k.contains("|"))
	extra.sort()
	for key in extra:
		var parts: PackedStringArray = String(key).split("|", true, 1)
		print("%s%s needs %s" % [kinds[parts[1]] + " " if parts[0] == "pickup" else "", parts[1], ", ".join(report.needs[key])])
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var summary := "%d rooms, %d of %d ledges reachable, %.1f s" % [data.rooms.size(), report.reached_ledges, report.total_ledges, seconds]
	if report.errors.is_empty():
		print("validate pass: " + summary)
	else:
		print("validate fail: %d problems, %s" % [report.errors.size(), summary])
	quit(0 if report.errors.is_empty() else 1)
