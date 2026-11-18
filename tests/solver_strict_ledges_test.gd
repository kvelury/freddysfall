extends TestCase

## `--strict-ledges` (StrictLedges): a ledge that is all doorway is not one a
## player can stand on, so it is not counted; every other ledge is.


func _initialize() -> void:
	watchdog(60.0)
	var ok := true
	# Room 1: a floor, and a one-cell door high in the right wall over solid wall,
	# as between rooms 16 and 18. Room 2: the same door in its left wall, with a
	# floor that runs into it.
	var first := {Vector2i(2, 16): "P", Vector2i(31, 5): "X"}
	var second := {Vector2i(0, 5): "X"}
	for x in range(0, 12):
		second[Vector2i(x, 6)] = "#"
	var errors: Array[String] = []
	var built := RoomParser.build([
		{"id": "1", "grid_pos": Vector2i(0, 0), "text": _room(first)},
		{"id": "2", "grid_pos": Vector2i(1, 0), "text": _room(second)},
	], "1", errors)
	ok = check(errors.is_empty(), "the rooms load %s" % [errors]) and ok
	var rooms: Dictionary = built["rooms"]
	var graph := ReachGraph.new(rooms, load("res://src/player/movement.tres"))
	var doorway := _ledge(graph, "1", 5, 31)
	ok = check(doorway != null and doorway.x0 == 31 and doorway.x1 == 31, "the doorway cell over the wall is a ledge to the solver") and ok
	ok = check(doorway != null and not StrictLedges.counted(rooms["1"], doorway), "but it is all doorway, so it is not counted") and ok
	var floor := _ledge(graph, "1", 16, 5)
	ok = check(floor != null and StrictLedges.counted(rooms["1"], floor), "a floor is counted") and ok
	var shelf := _ledge(graph, "2", 5, 0)
	ok = check(shelf != null and shelf.x0 == 0 and shelf.x1 == 11 and StrictLedges.counted(rooms["2"], shelf), "a shelf that runs into a doorway is counted") and ok
	finish("STRICT_LEDGES", ok)


func _ledge(graph: ReachGraph, room: String, row: int, x: int) -> ReachGraph.Ledge:
	for ledge in graph.ledges_in(room):
		if not ledge.moving and ledge.row == row and x >= ledge.x0 and x <= ledge.x1:
			return ledge
	return null


func _room(marks: Dictionary) -> String:
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += marks.get(Vector2i(x, y), "#" if edge else ".")
		rows.append(row)
	return "\n".join(rows) + "\n"
