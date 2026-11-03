class_name MoveProvider
extends RefCounted

## One way the player can move, as the solver sees it: the jumps from a ledge,
## or a search that adds some. ReachGraph holds these in a fixed order (ground,
## air, lash, imprint) and asks each one that applies. A new power the solver
## has to know about is a new provider.

var graph: ReachGraph


func _init(reach: ReachGraph) -> void:
	graph = reach


func key() -> String:
	return ""


## Whether the player can use this with what they have.
func applies(_abilities: Abilities) -> bool:
	return true


## Works out whatever this needs for the whole room, once.
func prepare(_info: RoomInfo) -> void:
	pass


## Where `ledge` can get to with this, already worked out by prepare.
func next(_ledge: ReachGraph.Ledge, _info: RoomInfo, _run: ReachGraph.Run) -> Moves:
	return Moves.new()


## A search that adds edges of its own. True if it opened somewhere new, and
## the flood should run again. One that finishes its own search returns false.
func expand(_run: ReachGraph.Run) -> bool:
	return false


## Whether a path of this kind from `ledge` takes the room's thing `index`.
func picked(_ledge: ReachGraph.Ledge, _run: ReachGraph.Run, _index: int) -> bool:
	return false


## The ledges, door touches and pickups one provider gives from one ledge.
class Moves extends RefCounted:
	var ledges: Array[ReachGraph.Ledge] = []
	var touches: Array[ReachGraph.Touch] = []
	var pickups: Array[int] = []
