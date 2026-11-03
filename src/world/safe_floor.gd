class_name SafeFloor
extends RefCounted

## The floors the player has stood on since they entered a room the hard way,
## newest last. Dying with a heart left puts them back on the last one, and a
## spot that kills again before they have stood anywhere is forgotten.

## How many stretches of floor are remembered.
const HISTORY := 8
## How far apart two spots have to be, in pixels, to count as different stretches.
const SPACING := 30.0

var spots: Array[Dictionary] = []
## Whether the player has stood on safe floor since they last came back from a death.
var stood_since_respawn := true


func record(room_id: String, at: Vector2) -> void:
	stood_since_respawn = true
	if not spots.is_empty():
		var last: Dictionary = spots[-1]
		if last["room"] == room_id and at.distance_to(last["anchor"]) < SPACING:
			last["position"] = at
			return
	spots.append({"room": room_id, "position": at, "anchor": at})
	if spots.size() > HISTORY:
		spots.pop_front()


func clear() -> void:
	spots.clear()


func last() -> Dictionary:
	return spots[-1]


func drop_last() -> void:
	if spots.size() > 1:
		spots.pop_back()
