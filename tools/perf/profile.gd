extends SceneTree

# Counts calls at the public plan boundary without altering the shipped solver.
class CountGraph extends ReachGraph:
	var simulations := 0
	var count_only := false
	func try_plan(info: RoomInfo, geo: Geometry, ledge: Ledge, near: Array[Rect2], x: float, speed: float, input: float, hold: int, jump: bool, limit := -1, tick := -1, top := NAN, riding := -1, air_frame := -1, air_hold := 0) -> void:
		simulations += 1
		if count_only:
			return
		super.try_plan(info, geo, ledge, near, x, speed, input, hold, jump, limit, tick, top, riding, air_frame, air_hold)

var cfg: MovementConfig = load("res://src/player/movement.tres")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("PERF ", JSON.stringify({"godot": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "processors": OS.get_processor_count(), "os": OS.get_name(), "units": "microseconds"}))
	for width in [32, 64]:
		var text := FileAccess.get_file_as_string("res://tests/fixtures/perf/floor-%d.txt" % width)
		var rooms := _parse(text)
		var info: RoomInfo = rooms["1"]
		var started := Time.get_ticks_usec()
		for i in 20:
			_parse(text)
		_emit("parse", {"width": width, "iterations": 20, "usec": Time.get_ticks_usec() - started})
		started = Time.get_ticks_usec()
		for i in 20:
			var room := Room.new()
			room.build(info)
			room.free()
		_emit("build", {"width": width, "iterations": 20, "usec": Time.get_ticks_usec() - started})
		var plain := _solve(rooms, null, "uncached", width)
		var cache := SolverCache.new(OS.get_environment("PERF_CACHE_ROOT").path_join(str(width)))
		# runner's fresh user directory makes this cold.
		var cold := _solve(rooms, cache, "cold", width)
		failed = failed or cache.stats.edge_rooms_cached != 0 or cache.stats.edge_rooms_solved != 1
		cache.save()
		var warm := _solve(rooms, SolverCache.new(OS.get_environment("PERF_CACHE_ROOT").path_join(str(width))), "warm", width)
		failed = failed or plain != cold or cold != warm
		var rows := text.split("\n")
		rows[13] = rows[13].substr(0, 10) + "##" + rows[13].substr(12)
		var edited := _parse("\n".join(rows))
		var changed := _solve(edited, SolverCache.new(OS.get_environment("PERF_CACHE_ROOT").path_join(str(width))), "single-room-change", width)
		failed = failed or changed != _solve(edited, null, "changed-uncached", width)
		var rects: Array[Rect2] = []
		for rect in info.all_solids():
			rects.append(Grid.cell_rect(rect))
		var state := MovementSim.State.new()
		state.position = Vector2(25, 165)
		started = Time.get_ticks_usec()
		for i in 3000:
			MovementSim.step(cfg, state, rects, 0, false, false, 1.0 / 60.0)
		_emit("physics-step", {"width": width, "iterations": 3000, "rectangles": rects.size(), "usec": Time.get_ticks_usec() - started})
	# Census is intentionally not a world solve. It locates the scaling inputs.
	var data = load("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	failed = failed or not data.errors.is_empty()
	var census := CountGraph.new(data.rooms, cfg)
	for id in data.rooms:
		var info: RoomInfo = data.rooms[id]
		var planner := CountGraph.new({id: info}, cfg)
		planner.count_only = true
		planner._ensure_edges(info)
		var ground_plans := planner.simulations
		planner._ensure_air_edges(info)
		var all_plans := planner.simulations
		if id == "12":
			var sample := CountGraph.new({id: info}, cfg)
			var geo := sample.geometry_of(info)
			var ledge := sample.ledges_in(id)[0]
			var near := sample.near_solids(geo.rects, ledge)
			var sample_started := Time.get_ticks_usec()
			for phase in sample.phases(info):
				sample.try_plan(info, geo, ledge, near, ledge.lo, 0, 1, 90, true, -1, phase)
			_emit("bounded-mover-plans", {"room": id, "simulations": sample.simulations, "frame_limit": sample.frame_limit, "usec": Time.get_ticks_usec() - sample_started})
		var movers := Movers.new(info.movers)
		var started := Time.get_ticks_usec()
		for tick in 600:
			movers.rects(tick)
		var mover_usec := Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		for i in 20:
			info.solver_variant([]).all_solids()
		var geometry_usec := Time.get_ticks_usec() - started
		var room := Room.new()
		room.build(info)
		started = Time.get_ticks_usec()
		for i in 3000:
			room.wall_at(Rect2(-100, -100, 1, 1))
		var query_usec := Time.get_ticks_usec() - started
		room.free()
		var starts := 0
		for ledge in census.ledges_in(id):
			if not ledge.moving:
				starts += census.start_xs(ledge).size()
		_emit("census", {"ground_scheduled_plans": ground_plans, "ground_plus_air_scheduled_plans": all_plans, "room": id, "cells": str(info.cell_size), "ledges": census.ledges_in(id).size(), "start_positions": starts, "phases": census.phases(info).size(), "mover_bodies": movers.size(), "cached_ticks": movers._cache.size(), "cached_body_samples": movers._cache.size() * movers.size(), "mover_600_ticks_usec": mover_usec, "geometry_20_rebuild_usec": geometry_usec, "tongue_3000_wall_misses_usec": query_usec, "walls": info.breakables.size(), "wall_subset_upper_bound": pow(2, info.breakables.size()), "wall_state_cap": ReachGraph.MAX_WALL_STATES})
	data.free()
	print("PERF equivalence ", "FAIL" if failed else "pass")
	quit(1 if failed else 0)

func _parse(text: String) -> Dictionary:
	var errors: Array[String] = []
	var result := RoomParser.build([{"id": "1", "grid_pos": Vector2i.ZERO, "text": text}], "1", errors)
	assert(errors.is_empty(), str(errors))
	return result.rooms

func _solve(rooms: Dictionary, cache: SolverCache, label: String, width: int) -> String:
	var started := Time.get_ticks_usec()
	var graph := CountGraph.new(rooms, cfg)
	graph.cache = cache
	var report := graph.solve("1")
	# Compare the public validation summary; gameplay/cache tests cover richer worlds.
	var answer := JSON.stringify([report.errors, report.warnings, report.reached_ledges, report.total_ledges, report.needs, report.pickups])
	_emit("validation", {"mode": label, "width": width, "height": 18, "usec": Time.get_ticks_usec() - started, "simulations": graph.simulations, "timing_ms": graph.timing(), "cache": cache.stats if cache != null else {}, "answer": answer.sha256_text()})
	return answer

func _emit(kind: String, fields: Dictionary) -> void:
	fields["kind"] = kind
	print("PERF ", JSON.stringify(fields))
