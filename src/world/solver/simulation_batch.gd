class_name SimulationBatch
extends RefCounted

## An ordered list of SimulationRequests that run against one ledge's geometry:
## the room (`info`, `geo`), the ledge they start from and the solids near it.
## The order is the order the solver used to try them in, and it is the order
## their results are applied in (`ReachGraph.run_batch`), whatever order they
## were run in. Running one request never depends on applying another's result,
## so a batch may be run in any order or in pieces; applying may not.
##
## Pure: it holds data and calls nothing in the scene or the autoloads.

var info: RoomInfo
var geo: ReachGraph.Geometry
var ledge: ReachGraph.Ledge
var near: Array[Rect2]
## The sets of solids a request can be tested against: `near` first, then any added.
var solid_sets: Array = []
var requests: Array[SimulationRequest] = []


func _init(room: RoomInfo, geometry: ReachGraph.Geometry, from: ReachGraph.Ledge, solids: Array[Rect2]) -> void:
	info = room
	geo = geometry
	ledge = from
	near = solids
	solid_sets = [solids]


## Another set of solids for requests to name (`SimulationRequest.solids`);
## returns its index.
func add_solids(rects: Array[Rect2]) -> int:
	solid_sets.append(rects)
	return solid_sets.size() - 1


## The solids request `ordinal` is tested against.
func solids_of(ordinal: int) -> Array[Rect2]:
	return solid_sets[requests[ordinal].solids]


## Appends a request; its ordinal is its index.
func add(request: SimulationRequest) -> void:
	requests.append(request)


func size() -> int:
	return requests.size()
