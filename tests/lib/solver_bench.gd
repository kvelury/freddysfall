extends SceneTree

## Prints one JSON line of what tools/solver_bench.py records about the inputs:
## the solver fingerprint, each room's fingerprint (what the cache keys a room
## by) and the Godot version. No solving.


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var rooms := {}
	var ids: Array = data.rooms.keys()
	ids.sort()
	for id in ids:
		rooms[id] = SolverCache.room_fingerprint(data.rooms[id])
	print("BENCH_INPUTS ", JSON.stringify({"solver": SolverCache.solver_fingerprint(), "rooms": rooms, "godot": Engine.get_version_info()["string"], "load_errors": data.errors.size()}))
	quit(0)
