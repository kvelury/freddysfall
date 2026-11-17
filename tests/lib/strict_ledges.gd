class_name StrictLedges
extends RefCounted

## Which unreached ledges `tools/validate.sh --strict-ledges` fails on.
##
## The solver calls any open cell over a solid one a ledge, so the cells of a
## doorway in a side wall that sits on the wall below it are a ledge too. A body
## standing there would be in the doorway and leave the room first, so nobody can
## stand on it, and it is not counted. Any ledge with a cell in the room proper
## still counts.


## Whether `ledge` of `info` must be reached under --strict-ledges.
static func counted(info: RoomInfo, ledge: ReachGraph.Ledge) -> bool:
	if ledge.moving:
		return true
	for x in range(ledge.x0, ledge.x1 + 1):
		var in_door := false
		for door in info.exits:
			in_door = in_door or door.rect.has_point(Vector2i(x, ledge.row))
		if not in_door:
			return true
	return false
