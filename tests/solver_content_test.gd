extends TestCase

## The solver's view of room 3 as drawn: nothing from the entrance ledge may land
## on the token's platform or the step beside it. This reads the real world, so
## update it when room 3 changes on purpose. Optional: it is run by
## `tools/check.sh --solver`.


func _initialize() -> void:
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var graph := ReachGraph.new(data.rooms, cfg)
	graph.room_ledges("3")
	check(_token_needs_the_climb(graph), "room 3's entrance ledge has no jump onto the token's platform or the step before it, and that step reaches the token")
	finish("SOLVER CONTENT")


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
