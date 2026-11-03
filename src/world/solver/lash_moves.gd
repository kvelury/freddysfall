class_name LashMoves
extends MoveProvider

## Breaking a wall with the tongue. A broken wall is a state of one visit: the
## ledge it opens is in the copy of the room with that wall broken.


func key() -> String:
	return "lash"


func applies(abilities: Abilities) -> bool:
	return abilities != null and abilities.tongue_unlocked


func next(ledge: ReachGraph.Ledge, info: RoomInfo, _run: ReachGraph.Run) -> MoveProvider.Moves:
	var out := MoveProvider.Moves.new()
	out.ledges = graph._lash_ledges(ledge, info)
	return out
