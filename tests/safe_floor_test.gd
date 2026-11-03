extends TestCase

## Safe floor is pure: one stretch while the player walks along it, a new
## stretch once they have gone far enough, and the oldest dropped past eight.


func _initialize() -> void:
	var floor := SafeFloor.new()
	floor.record("a", Vector2(0, 0))
	floor.record("a", Vector2(10, 0))
	check(floor.spots.size() == 1 and floor.spots[0]["position"] == Vector2(10, 0), "walking along one floor is one stretch")
	floor.record("a", Vector2(SafeFloor.SPACING + 1.0, 0))
	check(floor.spots.size() == 2, "a spot past the spacing is a new stretch")
	floor.record("b", Vector2(0, 0))
	check(floor.last()["room"] == "b", "the newest stretch is last")
	for i in 10:
		floor.record("c", Vector2(i * 100.0, 0))
	check(floor.spots.size() == SafeFloor.HISTORY, "only the newest stretches are kept")
	floor.stood_since_respawn = false
	floor.drop_last()
	check(floor.spots.size() == SafeFloor.HISTORY - 1, "a bad respawn spot is dropped")
	floor.clear()
	check(floor.spots.is_empty(), "a fresh placement forgets the old floors")
	finish("SAFE FLOOR")
