extends TestCase

## Checks that are about the rooms as they are drawn, not about a mechanic.
## Update this when you change these rooms on purpose. Mechanics tests build
## their own rooms, or load tests/fixtures/worlds.


func _initialize() -> void:
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var graph := ReachGraph.new(data.rooms, cfg)
	graph.room_ledges("3")
	check(_token_needs_the_climb(graph), "room 3's entrance ledge has no jump onto the token's platform or the step before it, and that step reaches the token")
	var four: RoomInfo = data.get_room("4")
	var nine: RoomInfo = data.get_room("9")
	check(_upgrade(four, "double_jump") and _upgrade(nine, "tongue_lash"), "room 4's machine gives double jump and room 9's gives tongue lash")
	check(data.get_room("s1").is_save_room(), "s1 is a save room")
	var pocket = preload("res://src/autoload/world_data.gd").new()
	pocket.load_from("res://tests/fixtures/worlds/pocket/world.json", "res://tests/fixtures/worlds/pocket/rooms/")
	check(pocket.errors.is_empty() and pocket.rooms.size() == 1 and pocket.start_room == "1", "a fixture world loads on its own (%s)" % [pocket.errors])
	finish("CONTENT")


func _upgrade(info: RoomInfo, upgrade: String) -> bool:
	for def in info.entities:
		if def.type == "machine" and String(def.props.get("upgrade", "")) == upgrade:
			return true
	return false


## The player arrives in room 3 on a ledge level with room 2. Nothing they
## can do from there, without Imprint, may land them on the token's platform or
## the step beside it: they climb the staircase to the right instead.
func _token_needs_the_climb(graph: ReachGraph) -> bool:
	var entrance: ReachGraph.Ledge = null
	var token: ReachGraph.Ledge = null
	var step: ReachGraph.Ledge = null
	for ledge in graph.ledges_in("3"):
		if ledge.row == 8 and ledge.x0 == 0:
			entrance = ledge
		elif ledge.row == 4 and ledge.x0 == 18:
			token = ledge
		elif ledge.row == 5 and ledge.x0 == 26:
			step = ledge
	if entrance == null or token == null or step == null:
		return false
	return not entrance.to_ledges.has(token.index) and not entrance.to_ledges.has(step.index) and step.to_ledges.has(token.index) and entrance.pickups.is_empty()
