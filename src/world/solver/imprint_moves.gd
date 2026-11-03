class_name ImprintMoves
extends MoveProvider

## Platforms the player can put down. The search adds its edges to the run, and
## finishes its own loop, so expand does not ask for another flood.


func key() -> String:
	return "imprint"


func applies(abilities: Abilities) -> bool:
	return abilities != null and abilities.imprint_unlocked


func next(ledge: ReachGraph.Ledge, _info: RoomInfo, run: ReachGraph.Run) -> MoveProvider.Moves:
	var out := MoveProvider.Moves.new()
	for found in run.extra_to.get(ledge, []):
		out.ledges.append(found)
	for touch in run.extra_touches.get(ledge, []):
		out.touches.append(touch)
	for index in run.extra_pickups.get(ledge, []):
		out.pickups.append(index)
	return out


func expand(run: ReachGraph.Run) -> bool:
	graph._place_imprints(run)
	return false


func picked(ledge: ReachGraph.Ledge, run: ReachGraph.Run, index: int) -> bool:
	return run.extra_pickups.get(ledge, []).has(index)
