extends SceneTree

## Loads the whole world, then checks it can be played: every room and door
## reachable from the start, and no place you cannot get back from.
## Exits non-zero on any error. Warnings (ledges nobody reached) do not fail.
## tools/validate.sh runs this. What the solver works out about each room is
## kept in build/solver-cache/ between runs, so a run after editing one room
## only redoes that room. `--no-cache` ignores and does not write it.
##
## `--dump=<path>` also writes everything the solver worked out, sorted, for
## tools/solver_diff.sh. `--strict-ledges` makes a ledge nobody reaches an
## error, as CI runs it. `--cache-dir=<path>` chooses the cache folder.
## `--warm=<id,id>` works out those rooms' jumps (and each set of their walls
## broken) into the cache and exits, so tools/validate.sh --jobs can share it
## across processes.

## How many room keys the timing table lists, slowest first.
const SLOWEST_SHOWN := 10


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
	var graph := ReachGraph.new(data.rooms, cfg)
	var cache_dir := _flag_value("--cache-dir")
	if cache_dir.is_empty():
		cache_dir = "res://build/solver-cache"
	var cache: SolverCache = null
	if not _has_flag("--no-cache"):
		cache = SolverCache.new(cache_dir)
		graph.cache = cache
	var warm_ids := _flag_value("--warm")
	if not warm_ids.is_empty():
		for id in warm_ids.split(",", false):
			graph.warm(id)
		var files := cache.save() if cache != null else 0
		print("warm %s %.1f s (%d files)" % [warm_ids, float(Time.get_ticks_msec() - started) / 1000.0, files])
		quit(0)
		return
	var report := graph.solve(data.start_room)
	var written := cache.save() if cache != null else 0
	if _has_flag("--strict-ledges"):
		for ledge in report.unreached:
			report.errors.append("%s cannot be reached (--strict-ledges)" % ledge.describe())
	var dump_path := _flag_value("--dump")
	if not dump_path.is_empty():
		_write_dump(dump_path, graph, report)
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
	var timing := graph.timing()
	print("time: ledges' jumps %.1f s, Imprint search %.1f s (jumps %.1f, landings %.1f, platforms' legs %.1f), %d platforms looked at, %d legs worked out" % [
		timing["edges"] / 1000.0,
		(timing["arcs"] + timing["lands"] + timing["legs"]) / 1000.0,
		timing["arcs"] / 1000.0,
		timing["lands"] / 1000.0,
		timing["legs"] / 1000.0,
		timing["candidates"],
		timing["legs_made"],
	])
	var slowest: Array = timing.get("rooms", [])
	if not slowest.is_empty():
		print("slowest rooms:")
		for i in mini(slowest.size(), SLOWEST_SHOWN):
			var row: Dictionary = slowest[i]
			print("  %-28s %8.1f s  %7d plans  %7d run once for every moment  %3d phases" % [row["key"], row["ms"] / 1000.0, row["plans"], row.get("reused", 0), row["phases"]])
	var totals := {}
	for row in slowest:
		var base := String(row["key"]).split("~", true, 1)[0].split(" ", true, 1)[0]
		totals[base] = float(totals.get(base, 0.0)) + float(row["ms"])
	if not totals.is_empty() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://build")):
		var times := FileAccess.open("res://build/room-times.json", FileAccess.WRITE)
		if times != null:
			times.store_string(JSON.stringify(totals))
			times.close()
	if cache != null:
		print("cache: %d rooms' ledges from it and %d worked out, %d legs from it and %d worked out, %d files written" % [cache.stats["edge_rooms_cached"], cache.stats["edge_rooms_solved"], cache.stats["legs_cached"], cache.stats["legs_solved"], written])
	else:
		print("cache: off")
	var summary := "%d rooms, %d of %d ledges reachable, %.1f s" % [data.rooms.size(), report.reached_ledges, report.total_ledges, seconds]
	if report.errors.is_empty():
		print("validate pass: " + summary)
	else:
		print("validate fail: %d problems, %s" % [report.errors.size(), summary])
	quit(0 if report.errors.is_empty() else 1)


func _has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


## The value of `name=value` among the arguments after `--`, or "".
func _flag_value(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="):
			return arg.substr(name.length() + 1)
	return ""


func _write_dump(path: String, graph: ReachGraph, report: ReachGraph.Report) -> void:
	var pickups := []
	for pickup in report.pickups:
		pickups.append(pickup)
	pickups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var errors := report.errors.duplicate()
	errors.sort()
	var warnings := report.warnings.duplicate()
	warnings.sort()
	var data := {"graph": preload("res://tests/lib/solver_dump.gd").dump(graph), "needs": report.needs, "errors": errors, "warnings": warnings, "pickups": pickups}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("FAIL could not write the dump to %s" % path)
		return
	file.store_string(JSON.stringify(data, "  ", true))
	file.close()
	print("dump: %s" % path)
