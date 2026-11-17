extends SceneTree

## Solves the world (no cache, one process) and writes SolverDump's data to
## `--dump=<path>`, for tools/solver_diff.sh. It depends only on what an old
## checkout has (the world loader, ReachGraph, MovementConfig and the report's
## fields), so solver_diff.sh can copy it with solver_dump.gd into a base ref
## without copying tests/validate.gd and whatever that has grown to need.
##
## The dump is written to `<path>.partial` and renamed only when it is whole, and
## ends with `"complete": true`: a crash or a kill leaves no dump to be read as a
## result. Exit 0 means the dump is complete (the world may still have validator
## errors; they are in the dump, which fixture comparisons want); 1 the world did
## not load; 2 no `--dump`; `--world=<folder>` solves a fixture world instead; 3 the dump could not be written.


func _initialize() -> void:
	var path := ""
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			path = arg.substr(7)
		elif arg.begins_with("--world="):
			fixture = arg.substr(8)
	if path.is_empty():
		print("FAIL solver_dump_main needs --dump=<path>")
		quit(2)
		return
	var data = preload("res://src/autoload/world_data.gd").new()
	if fixture.is_empty():
		data.ensure_loaded()
	else:
		# A small fixture world (a folder holding world.json and rooms/).
		data.load_from(fixture.path_join("world.json"), fixture.path_join("rooms") + "/")
	if not data.errors.is_empty():
		for message in data.errors:
			print("FAIL ", message)
		quit(1)
		return
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var graph := ReachGraph.new(data.rooms, cfg)
	var report := graph.solve(data.start_room)
	var pickups := []
	for pickup in report.pickups:
		pickups.append(pickup.row())
	pickups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var errors := report.errors.duplicate()
	errors.sort()
	var warnings := report.warnings.duplicate()
	warnings.sort()
	var out := {"graph": preload("res://tests/lib/solver_dump.gd").dump(graph), "needs": report.needs, "errors": errors, "warnings": warnings, "pickups": pickups, "complete": true}
	var temp := path + ".partial"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		print("FAIL could not write %s" % temp)
		quit(3)
		return
	file.store_string(JSON.stringify(out, "  ", true))
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		print("FAIL could not move %s to %s" % [temp, path])
		quit(3)
		return
	print("dump complete: %s (%d validator errors)" % [path, errors.size()])
	quit(0)
