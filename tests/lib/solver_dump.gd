extends RefCounted

## Everything a solved ReachGraph worked out, as plain sorted data that names
## ledges and things by what they are, not by index, so two runs can be
## compared line by line: every room key's ledges with what they reach (`to`),
## their door touches and pickups, the same for air jumps, and where each door
## touch lands. tools/solver_diff.sh copies this file into an older checkout,
## so it reads the graph's fields by name and needs nothing newer than they are.
##
## Beyond that set, it keeps what a sorted set would hide:
## - `touches_exact`: each ledge's door touches in the order retained, with the
##   exact position and velocity (the first touch for a rounded key wins, so a
##   different winner is a different graph even when the keys agree);
## - `climb`: each Tongue Climb store (`ClimbMoves._stores`, when the graph has
##   them): its hangs in discovery order with where they are, their links and
##   what they land on, the sticks tried (which hang or none), the ceiling
##   samples (the first representative per cell, `[]` for a failed one), and
##   what each ledge's climbing reaches (`moves`), touches in order.
## Sets are sorted for presentation; first-winner values and orders are not.


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
				"touches_exact": _touches_exact(ledge.touches),
				"air_touches_exact": _touches_exact(ledge.air_touches),
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
	return {"rooms": rooms, "landings": landings, "climb": _climb(graph)}


## The Tongue Climb stores, or {} for a graph without them. Keys are
## `<room key>|<signature>`, as ClimbMoves keeps them.
static func _climb(graph) -> Dictionary:
	var out := {}
	for provider in graph._providers:
		if provider.key() != "climb" or not "_stores" in provider:
			continue
		var stores: Dictionary = provider._stores
		var names: Array = stores.keys()
		names.sort()
		for name in names:
			var store = stores[name]
			var room_key := String(name).split("|", true, 1)[0]
			if not graph._ledges.has(room_key):
				continue
			var ledges: Array = graph._ledges[room_key]
			var info: RoomInfo = graph._info_of(room_key)
			var things: Array = graph._things_of(info)
			var hangs := []
			var order := 0
			for key in store.hangs:
				var hang = store.hangs[key]
				var links := []
				for link in hang.links:
					links.append(link.key)
				var entry := {"order": order, "key": String(key), "pos": _vec(hang.pos), "dir": hang.dir, "wall": hang.wall, "expanded": hang.expanded, "links": links}
				if hang.land != null:
					entry["land"] = _ledge_data(ledges, things, hang.land)
				if hang.broken_land != null:
					entry["broken_land"] = "%s %s" % [hang.broken_land.room_id, hang.broken_land.describe()]
				hangs.append(entry)
				order += 1
			var sticks := {}
			for key in store.sticks:
				sticks[String(key)] = null if store.sticks[key] == null else store.sticks[key].key
			var sampled := {}
			for key in store.sampled:
				sampled[String(key)] = store.sampled[key]
			var moves := {}
			for ledge in store.moves:
				var m = store.moves[ledge]
				var reach: Array[String] = []
				for target in m.ledges:
					reach.append("%s %s" % [target.room_id, target.describe()])
				reach.sort()
				moves["%s %s" % [ledge.room_id, ledge.describe()]] = {"ledges": reach, "touches": _touches_exact(m.touches), "pickups": _thing_ids(things, m.pickups)}
			out[name] = {"hangs": hangs, "sticks": sticks, "sampled": sampled, "moves": moves}
	return out


static func _ledge_data(ledges: Array, things: Array, ledge) -> Dictionary:
	return {
		"to": _describe_all(ledges, ledge.to_ledges),
		"touches": _touches_exact(ledge.touches),
		"pickups": _thing_ids(things, ledge.pickups),
		"air_to": _describe_all(ledges, ledge.air_to_ledges),
		"air_touches": _touches_exact(ledge.air_touches),
		"air_pickups": _thing_ids(things, ledge.air_pickups),
	}


## One line per touch, in retained order: door, then position and velocity to
## six places (a Vector2 is 32-bit, so this is exact enough to see any change).
static func _touches_exact(touches: Array) -> Array[String]:
	var out: Array[String] = []
	for touch in touches:
		out.append("%d|%s|%s" % [touch.door, _vec(touch.position), _vec(touch.velocity)])
	return out


static func _vec(v: Vector2) -> String:
	return "%.6f,%.6f" % [v.x, v.y]


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
