extends TestCase

## SimulationRequest and SimulationBatch: the request codec (optional values are
## explicit, nothing is rounded, a bad record is refused), that two requests that
## differ in any input never share an identity (a different start tick, rider
## body or hang is a different request), and that the solver gives the same
## answers whatever order a batch's requests are run in, because results are
## applied in request order.

const WORLD := "res://tests/fixtures/worlds/synth/"


func _initialize() -> void:
	var ok := _codec()
	ok = _identity() and ok
	ok = _refused() and ok
	ok = _order() and ok
	finish("SOLVER BATCH", ok)


func _same(a: SimulationRequest, b: SimulationRequest) -> bool:
	return a.identity() == b.identity()


func _codec() -> bool:
	var ok := true
	var plain := SimulationRequest.make(123.456789012345, -45.0, 1.0, 12, true, 90, 7, NAN, -1, 6, 40)
	var back := SimulationRequest.from_dict(JSON.parse_string(JSON.stringify(plain.to_dict())))
	ok = check(back != null and _same(plain, back), "a request survives JSON, with no top (NAN) and no hang") and ok
	ok = check(back != null and is_nan(back.top) and back.hang == Vector2.ZERO and back.x == plain.x, "NAN comes back as NAN, ZERO as ZERO, and x to the last digit") and ok
	var odd := SimulationRequest.make(0.1 + 0.2, 1e-7, -1.0, 0, false, -1, -1, 4.0000001, 3, -1, 0, Vector2(0.0, -1.0), 1)
	back = SimulationRequest.from_dict(JSON.parse_string(JSON.stringify(odd.to_dict())))
	ok = check(back != null and _same(odd, back) and back.top == odd.top and back.hang == odd.hang and back.riding == 3 and back.solids == 1 and back.x == odd.x, "an explicit top, a rider body, a ceiling hang and awkward floats round-trip exactly") and ok
	ok = check(not JSON.stringify(plain.to_dict()).contains("nan"), "the encoded form holds no NAN") and ok
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var drift := 0
	for i in 20000:
		var r := SimulationRequest.make(rng.randf_range(-3000.0, 3000.0) * pow(10.0, rng.randi_range(-6, 2)), rng.randf_range(-500.0, 500.0), rng.randf_range(-1.0, 1.0), rng.randi_range(0, 90), rng.randf() < 0.5, rng.randi_range(-1, 400), rng.randi_range(-1, 5000), rng.randf_range(0.0, 1000.0), rng.randi_range(-1, 9))
		var d := SimulationRequest.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
		if d == null or d.x != r.x or d.speed != r.speed or d.input != r.input or d.top != r.top or d.identity() != r.identity():
			drift += 1
	ok = check(drift == 0, "20000 random requests come back bit for bit through JSON text (%d differ)" % drift) and ok
	return ok


func _identity() -> bool:
	var base := SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2)
	var ok := true
	var variants := {
		"start tick": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 11, 100.0, 2),
		"rider body": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 3),
		"standing height": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 101.0, 2),
		"no standing height": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, NAN, 2),
		"hang": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2, -1, 0, Vector2(1.0, 0.0)),
		"hang direction": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2, -1, 0, Vector2(-1.0, 0.0)),
		"air frame": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2, 4, 0),
		"frame limit": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, 60, 10, 100.0, 2),
		"jump": SimulationRequest.make(50.0, 0.0, 1.0, 5, false, -1, 10, 100.0, 2),
		"solid set": SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2, -1, 0, Vector2.ZERO, 1),
	}
	for name in variants:
		ok = check(not _same(base, variants[name]), "a different %s is a different request" % name) and ok
	ok = check(_same(base, SimulationRequest.make(50.0, 0.0, 1.0, 5, true, -1, 10, 100.0, 2)), "equal inputs are one identity") and ok
	return ok


func _refused() -> bool:
	var good := SimulationRequest.make(1.0, 0.0, 0.0, 0, true).to_dict()
	var ok := check(SimulationRequest.from_dict(good) != null, "a good record decodes")
	var cases := {}
	var wrong := good.duplicate()
	wrong["protocol"] = SimulationRequest.PROTOCOL + 1
	cases["another protocol"] = wrong
	wrong = good.duplicate()
	wrong.erase("tick")
	cases["a missing field"] = wrong
	wrong = good.duplicate()
	wrong["x"] = SimulationRequest._encode(NAN)
	cases["a NAN x"] = wrong
	wrong = good.duplicate()
	wrong["speed"] = SimulationRequest._encode(INF)
	cases["an infinite speed"] = wrong
	wrong = good.duplicate()
	wrong["x"] = 1.5
	cases["a plain number for x"] = wrong
	wrong = good.duplicate()
	wrong["x"] = "00ff"
	cases["a short hex x"] = wrong
	wrong = good.duplicate()
	wrong["hold"] = "3"
	cases["a string hold"] = wrong
	wrong = good.duplicate()
	wrong["hold"] = 2.5
	cases["a fractional hold"] = wrong
	wrong = good.duplicate()
	wrong["jump"] = 1
	cases["a number for jump"] = wrong
	wrong = good.duplicate()
	wrong["hang"] = [1.0]
	cases["a short hang"] = wrong
	wrong = good.duplicate()
	wrong["top"] = SimulationRequest._encode(NAN)
	cases["a NAN top"] = wrong
	for name in cases:
		ok = check(SimulationRequest.from_dict(cases[name]) == null, "%s is refused" % name) and ok
	return ok


## Runs the requests of every batch last to first and hands the results back in
## request order, as workers that finish in any order would.
func _backwards(graph: ReachGraph) -> Callable:
	return func(batch: SimulationBatch) -> Array:
		var results: Array = []
		results.resize(batch.size())
		for i in range(batch.size() - 1, -1, -1):
			results[i] = graph.run_plan(batch.info, batch.geo, batch.ledge, batch.solids_of(i), batch.requests[i])
		return results


func _dump(backwards: bool) -> String:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.load_from(WORLD + "world.json", WORLD + "rooms/")
	var graph := ReachGraph.new(data.rooms, load("res://src/player/movement.tres") as MovementConfig)
	if backwards:
		graph.batch_executor = _backwards(graph)
	graph.solve(data.start_room)
	return JSON.stringify(preload("res://tests/lib/solver_dump.gd").dump(graph), "", true)


func _order() -> bool:
	var forward := _dump(false)
	var reversed := _dump(true)
	return check(forward == reversed, "solving with every batch run last to first dumps exactly what in-order does (ledges, exact touches, climb hangs)")
