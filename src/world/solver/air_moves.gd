class_name AirMoves
extends MoveProvider

## The same jumps with one air jump. The solver does not model more than one.


func key() -> String:
	return "air"


func applies(abilities: Abilities) -> bool:
	return abilities != null and abilities.air_jumps > 0


func prepare(info: RoomInfo) -> void:
	graph._ensure_air_edges(info)


func next(ledge: ReachGraph.Ledge, _info: RoomInfo, _run: ReachGraph.Run) -> MoveProvider.Moves:
	var out := MoveProvider.Moves.new()
	for index in ledge.air_to_ledges:
		out.ledges.append(graph._ledges_of(ledge.room_id)[index])
	out.touches = ledge.air_touches
	out.pickups = ledge.air_pickups
	return out


func picked(ledge: ReachGraph.Ledge, _run: ReachGraph.Run, index: int) -> bool:
	return ledge.air_pickups.has(index)
