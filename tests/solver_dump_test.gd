extends TestCase

## The solver dump (tests/lib/solver_dump.gd) keeps what tools/solver_diff.sh must
## be able to see: the exact door touch retained, the climb stores' hangs in order,
## their ceiling samples. Solves the small `synth` fixture (a pickup for each
## power, a lift, a ceiling, a breakable wall, a door) twice, then checks the dumps
## agree, are not empty, and tell two touches with one rounded key apart.

const WORLD := "res://tests/fixtures/worlds/synth/"


func _initialize() -> void:
	var first := _solve()
	var second := _solve()
	var ok := check(JSON.stringify(first, "", true) == JSON.stringify(second, "", true), "two solves of one world dump the same")
	var climb: Dictionary = first["climb"]
	ok = check(climb.size() >= 2, "the dump has the climb stores, including the broken-wall copy (%d)" % climb.size()) and ok
	var hangs := 0
	var sampled := 0
	var moves := 0
	for name in climb:
		hangs += (climb[name]["hangs"] as Array).size()
		sampled += (climb[name]["sampled"] as Dictionary).size()
		moves += (climb[name]["moves"] as Dictionary).size()
	ok = check(hangs > 0 and sampled > 0 and moves > 0, "with hangs, ceiling samples and moves (%d, %d, %d)" % [hangs, sampled, moves]) and ok
	var exact := 0
	for key in first["rooms"]:
		for ledge in first["rooms"][key].values():
			exact += (ledge["touches_exact"] as Array).size()
	ok = check(exact > 0, "and the exact door touches (%d)" % exact) and ok
	ok = check(_first_winner(), "the first of two touches with one rounded key is what the dump shows") and ok
	finish("SOLVER DUMP", ok)


func _solve() -> Dictionary:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.load_from(WORLD + "world.json", WORLD + "rooms/")
	var graph := ReachGraph.new(data.rooms, load("res://src/player/movement.tres") as MovementConfig)
	graph.solve(data.start_room)
	return preload("res://tests/lib/solver_dump.gd").dump(graph)


func _first_winner() -> bool:
	var ledge := ReachGraph.Ledge.new()
	ledge.add_touch(0, Vector2(100.0, 50.0), Vector2(90.0, 0.0))
	ledge.add_touch(0, Vector2(101.0, 51.0), Vector2(91.0, 1.0))
	var a: Array[String] = preload("res://tests/lib/solver_dump.gd")._touches_exact(ledge.touches)
	return ledge.touches.size() == 1 and a == ["0|100.000000,50.000000|90.000000,0.000000"]
