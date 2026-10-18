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
	var report := ReachGraph.new(data.rooms, cfg).analyze(data.start_room)
	for message in report.errors:
		print("FAIL ", message)
	for message in report.warnings:
		print("warn ", message)
	for pickup in report.pickups:
		print("pickup %s in room %s: %s %s%s" % [pickup["id"], pickup["room"], pickup["upgrade"], pickup["value"], "" if pickup["reached"] else "  (not reached)"])
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var summary := "%d rooms, %d of %d ledges reachable, %.1f s" % [data.rooms.size(), report.reached_ledges, report.total_ledges, seconds]
	if report.errors.is_empty():
		print("validate pass: " + summary)
	else:
		print("validate fail: %d problems, %s" % [report.errors.size(), summary])
	quit(0 if report.errors.is_empty() else 1)
