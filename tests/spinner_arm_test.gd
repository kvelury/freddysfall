extends TestCase

## A cross built from spinners that turn about one point (`pivot=`), with a
## breakable arm: how it loads, which way its side spikes point, the rules for
## spinners that share a pivot, what the tongue hits (the game and the solver ask
## `TongueReach` the same thing), and an arm breaking and growing back.

const PERIOD := 8
const LEGEND := """legend:
  N = spinner id=up period=8 pivot=16,9 spikes=left+right
  S = spinner id=down period=8 pivot=16,9 breakable=true
  W = spinner id=left period=8 pivot=16,9 spikes=top
  E = spinner id=right period=8 pivot=16,9 spikes=top+bottom
  C = spinner id=hub period=8 pivot=16,9
---
"""


func _initialize() -> void:
	watchdog(120.0)
	var ok := true
	ok = _parser() and ok
	ok = _facing() and ok
	ok = _movers() and ok
	ok = _reach() and ok
	ok = _variant() and ok
	ok = await _room() and ok
	finish("SPINNER ARM", ok)


## A room with a cross turning about the corner of cells (16, 9): a hub of 2 x 2
## and an arm of 4 on each side.
static func _rows() -> Array[String]:
	var rows: Array[String] = []
	for y in 18:
		rows.append("#" + ".".repeat(30) + "#")
	rows[0] = "#".repeat(32)
	rows[17] = "#".repeat(32)
	for y in range(4, 8):
		rows[y] = _put(rows[y], 15, "NN")
	for y in range(10, 14):
		rows[y] = _put(rows[y], 15, "SS")
	for y in range(8, 10):
		rows[y] = _put(rows[y], 11, "WWWW")
		rows[y] = _put(rows[y], 15, "CC")
		rows[y] = _put(rows[y], 17, "EEEE")
	return rows


static func _put(row: String, at: int, text: String) -> String:
	return row.substr(0, at) + text + row.substr(at + text.length())


static func _parse(legend := LEGEND) -> Array:
	var errors: Array[String] = []
	var info := RoomParser.parse_room("t", Vector2i.ZERO, legend + "\n".join(_rows()), errors)
	return [info, errors]


func _parser() -> bool:
	var ok := true
	var made := _parse()
	var info: RoomInfo = made[0]
	var errors: Array = made[1]
	ok = check(info != null and errors.is_empty(), "a cross of five spinners about one pivot loads (%s)" % [errors]) and ok
	if info == null:
		return false
	ok = check(info.spinners.size() == 5 and info.movers.size() == 5, "five movers") and ok
	ok = check(info.spinners[0].pivot == Vector2(160, 90) and info.spinners[1].pivot == Vector2(160, 90), "they share the pivot given, not the middle of their own rectangles") and ok
	ok = check(info.breakable_arms().size() == 1 and info.breakable_arm("down") != null and info.breakable_arm("up") == null, "only the down arm is breakable") and ok
	var legend := LEGEND.replace("N = spinner id=up period=8", "N = spinner id=up period=5")
	made = _parse(legend)
	ok = check(not (made[1] as Array).is_empty() and "same period" in String(made[1][0]), "spinners about one point with different periods are refused (%s)" % [made[1]]) and ok
	made = _parse(LEGEND.replace("pivot=16,9 breakable=true", "pivot=16,9 breakable=yes"))
	ok = check(not (made[1] as Array).is_empty() and "breakable=" in String(made[1][0]), "breakable=yes is refused (%s)" % [made[1]]) and ok
	made = _parse(LEGEND.replace("id=left period=8 pivot=16,9", "id=left period=8 pivot=sixteen"))
	ok = check(not (made[1] as Array).is_empty() and "pivot=" in String(made[1][0]), "a pivot that is not x,y is refused (%s)" % [made[1]]) and ok
	# A spinner that is not part of the cross still may not sweep over it.
	var rows := _rows()
	rows[3] = _put(rows[3], 16, "#")
	var errors2: Array[String] = []
	RoomParser.parse_room("t", Vector2i.ZERO, LEGEND + "\n".join(rows), errors2)
	ok = check(not errors2.is_empty() and "sweeps" in errors2[0], "a wall in the cross's sweep is still refused (%s)" % [errors2]) and ok
	return ok


func _facing() -> bool:
	var ok := true
	var info: RoomInfo = _parse()[0]
	var up: SpinnerPath = info.spinners[0]
	# A 2 x 4 arm with left+right spikes: every block is spiked, the left column
	# pointing left and the right column right, as drawn.
	var lefts := 0
	var rights := 0
	for body in up.body_count():
		ok = check(up.is_hazard(body), "every block of the up arm is spiked") and ok
		if up.normals[body] == Vector2.LEFT:
			lefts += 1
		elif up.normals[body] == Vector2.RIGHT:
			rights += 1
	ok = check(lefts == 4 and rights == 4, "four teeth point left and four right (%d, %d)" % [lefts, rights]) and ok
	# Turned with the bar: a quarter turn later (counter-clockwise) the left
	# column's teeth, which pointed left, have the same count of lit pixels.
	var left_body := 0
	var base := 0
	for run in up.teeth_at(0, left_body):
		base += int(run.size.x)
	var later := 0
	for run in up.teeth_at(PERIOD * 15, left_body):
		later += int(run.size.x)
	ok = check(base > 0 and base == later, "the teeth are the same picture a quarter turn later (%d, %d)" % [base, later]) and ok
	var left_arm: SpinnerPath = info.spinners[2]
	var spiked := 0
	for body in left_arm.body_count():
		if left_arm.is_hazard(body):
			spiked += 1
			ok = check(left_arm.normals[body] == Vector2.UP, "a top row's teeth point up") and ok
	ok = check(spiked == 4, "the left arm's top row is spiked and its bottom is not (%d)" % spiked) and ok
	var down: SpinnerPath = info.spinners[1]
	var plain := true
	for body in down.body_count():
		plain = plain and not down.is_hazard(body)
	ok = check(plain, "the breakable down arm has no spikes") and ok
	return ok


func _movers() -> bool:
	var ok := true
	var info: RoomInfo = _parse()[0]
	var movers := Movers.new(info.movers)
	var down_at := Vector2(160, 135)
	var probe := Rect2(down_at - Vector2(1, 1), Vector2(2, 2))
	ok = check(info.movers[1].id == "down" and movers.breakable_at(probe, 0) == 1, "a probe in the down arm finds it (mover 1)") and ok
	ok = check(movers.breakable_at(Rect2(Vector2(160, 45), Vector2(2, 2)), 0) == -1, "the spiked up arm is not breakable, and is not found") and ok
	var rects: Dictionary = movers.breakable_rects(0)
	ok = check(rects.size() == 1 and _area(rects["down"] as Array) == 8 * 100, "the solver is given the down arm's 8 blocks, as pixels") and ok
	movers.replace(1, (info.movers[1] as SpinnerPath).broken_copy())
	ok = check(movers.breakable_at(probe, 0) == -1 and movers.breakable_rects(0).is_empty(), "swapped for its broken copy it is not there to hit") and ok
	ok = check(not (info.movers[1] as SpinnerPath).gone, "the room's own list is untouched") and ok
	ok = check(_area(movers.rects(0)) == (4 + 4) * 100 and _area(movers.hazard_rects(0)) == (8 + 4 + 8) * 100, "the other arms still hold up (hub and left arm's bottom) and kill") and ok
	return ok


func _reach() -> bool:
	var ok := true
	var info: RoomInfo = _parse()[0]
	var movers := Movers.new(info.movers)
	# From a point under the arm, going up: the arm is hit before anything solid,
	# and by its id. With it broken the tongue goes on to the ceiling.
	var origin := Vector2(165, 165)
	var hit := TongueReach.first_hit(info, origin, Vector2.UP, 60.0, movers.rects(0), movers.breakable_rects(0))
	ok = check(hit["wall"] == "down" and hit["solid"], "a tongue going up meets the down arm, by id (%s)" % [hit]) and ok
	var broken := info.variant(["down"] as Array[String])
	var bm := Movers.new(broken.movers)
	hit = TongueReach.first_hit(broken, origin, Vector2.UP, 60.0, bm.rects(0), bm.breakable_rects(0))
	ok = check(hit["wall"] == "" and bm.breakable_rects(0).is_empty(), "with the arm broken the tongue is not stopped by it (%s)" % [hit]) and ok
	return ok


func _variant() -> bool:
	var ok := true
	var info: RoomInfo = _parse()[0]
	var broken := info.solver_variant(["down"] as Array[String])
	ok = check(broken.movers.size() == info.movers.size() and broken.movers[1].id == "down" and (broken.movers[1] as SpinnerPath).gone, "the solver's copy has the arm gone, in the same place in the list") and ok
	ok = check(not (broken.movers[0] as SpinnerPath).gone and broken.movers[0] == info.movers[0], "the others are shared") and ok
	ok = check(broken.spinners[1] == broken.movers[1], "the copy's spinners and movers agree") and ok
	ok = check(not (info.movers[1] as SpinnerPath).gone, "the room as loaded is untouched") and ok
	ok = check(broken.id == "t~down" and broken.base() == "t", "the copy has a key of its own (%s)" % broken.id) and ok
	var copy := (info.movers[1] as SpinnerPath).broken_copy()
	ok = check(copy.body_count() == 8 and not copy.alive_at(0, 0) and copy.period() == info.movers[1].period() and copy.pivot == info.movers[1].pivot, "a broken copy keeps its shape and has no body standing") and ok
	return ok


func _room() -> bool:
	var ok := true
	var info: RoomInfo = _parse()[0]
	var room := Room.new()
	room.build(info)
	root.add_child(room)
	var probe := Rect2(Vector2(160, 135) - Vector2(1, 1), Vector2(2, 2))
	var arm := room.arm_at(probe)
	ok = check(arm == 1, "the room finds the down arm under a probe (%d)" % arm) and ok
	ok = check(not room.hit_arm(arm, 2), "one lash of two does not break it") and ok
	ok = check(room.arm_at(probe) == 1, "it still stands, and holds up") and ok
	var floor_blocks := _area(room.mover_rects())
	var broke := room.hit_arm(arm, 2)
	ok = check(broke, "the second lash breaks it") and ok
	ok = check(room.arm_at(probe) == -1 and _area(room.mover_rects()) == floor_blocks - 8 * 100, "now it is gone: 8 blocks fewer hold anyone up (%d to %d px)" % [floor_blocks, _area(room.mover_rects())]) and ok
	ok = check(room.info.broken.has("down"), "the room's copy remembers it is broken") and ok
	ok = check(not (info.movers[1] as SpinnerPath).gone and not info.broken.has("down"), "the room as loaded is untouched") and ok
	# Strength 1 (the dev setting) breaks it with one lash.
	var again := Room.new()
	again.build(info)
	root.add_child(again)
	ok = check(again.arm_at(probe) == 1, "built again, the arm is back") and ok
	ok = check(again.hit_arm(1, 1), "a wall strength of 1 breaks it in one lash") and ok
	room.queue_free()
	again.queue_free()
	await process_frame
	return ok


## The pixels the rects cover, for rects that do not overlap.
static func _area(rects: Array) -> int:
	var total := 0
	for r: Rect2 in rects:
		total += int(r.size.x * r.size.y)
	return total
