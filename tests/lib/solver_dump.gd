extends RefCounted

## Everything a solved ReachGraph worked out, as plain sorted data that names
## ledges and things by what they are, not by index, so two runs can be
## compared line by line: every room key's ledges with what they reach (`to`),
## their door touches and pickups, the same for air jumps, and where each door
## touch lands. tools/solver_diff.sh copies this file into an older checkout,
## so it reads the graph's fields by name and needs nothing newer than they are.


static func dump(graph) -> Dictionary:
	var ledges_by_key: Dictionary = graph._ledges
	var rooms := {}
	var keys: Array = ledges_by_key.keys()
	keys.sort()
	for key in keys:
		var info: RoomInfo = graph._info_of(key)
		var things: Array = graph._things_of(info)
		var ledges := {}
		for ledge in ledges_by_key[key]:
			ledges[ledge.describe()] = {
				"to": _describe_all(ledges_by_key[key], ledge.to_ledges),
				"touches": _touch_keys(ledge.touches),
				"pickups": _thing_ids(things, ledge.pickups),
				"air_to": _describe_all(ledges_by_key[key], ledge.air_to_ledges),
				"air_touches": _touch_keys(ledge.air_touches),
				"air_pickups": _thing_ids(things, ledge.air_pickups),
			}
		rooms[key] = ledges
	var landings := {}
	var by_touch: Dictionary = graph._landings
	for key in by_touch:
		var names: Array[String] = []
		for ledge in by_touch[key]:
			names.append("%s %s" % [ledge.room_id, ledge.describe()])
		names.sort()
		landings[key] = names
	return {"rooms": rooms, "landings": landings}


static func _describe_all(ledges: Array, indices: Array) -> Array[String]:
	var out: Array[String] = []
	for index in indices:
		out.append(ledges[index].describe())
	out.sort()
	return out


static func _touch_keys(touches: Array) -> Array[String]:
	var out: Array[String] = []
	for touch in touches:
		out.append(touch.key())
	out.sort()
	return out


static func _thing_ids(things: Array, indices: Array) -> Array[String]:
	var out: Array[String] = []
	for index in indices:
		out.append(things[index].id)
	out.sort()
	return out
