class_name GroundMoves
extends MoveProvider

## Walking, jumping and dropping from a ledge, with no air jump.


func key() -> String:
	return "ground"


func prepare(info: RoomInfo) -> void:
	graph._ensure_edges(info)


func next(ledge: ReachGraph.Ledge, _info: RoomInfo, _run: ReachGraph.Run) -> MoveProvider.Moves:
	var out := MoveProvider.Moves.new()
	for index in ledge.to_ledges:
		out.ledges.append(graph._ledges_of(ledge.room_id)[index])
	out.touches = ledge.touches
	out.pickups = ledge.pickups
	return out


func picked(ledge: ReachGraph.Ledge, _run: ReachGraph.Run, index: int) -> bool:
	return ledge.pickups.has(index)
