extends TestCase

## Emitters: the room format (a row of the glyph against solid wall, track on
## to spikes or solid), the platforms' lives (fixed slots, one trip each, gone
## at the end), and play (a rider is carried until theirs breaks, then falls).

const DT := 1.0 / 60.0

const LEGEND := "legend:\n  E = emitter id=e1 speed=60 every=2\n---\n"


func _initialize() -> void:
	watchdog(120.0)
	var ok := true
	ok = _parser() and ok
	ok = _path() and ok
	ok = _sim() and ok
	finish("EMITTER", ok)


static func _room(rows: Array[String], legend := LEGEND) -> String:
	return legend + "\n".join(rows)


static func _parse(rows: Array[String], legend := LEGEND) -> Array:
	var errors: Array[String] = []
	var info := RoomParser.parse_room("t", Vector2i.ZERO, _room(rows, legend), errors)
	return [info, errors]


## 32 wide, 18 tall; a floor, the machine at the left wall, track to spikes.
static func _good() -> Array[String]:
	var rows: Array[String] = []
	for y in 18:
		rows.append("#" + ".".repeat(30) + "#")
	rows[0] = "#".repeat(32)
	rows[17] = "#".repeat(32)
	rows[16] = "#" + "EEEE" + "-".repeat(12) + "^" + ".".repeat(13) + "#"
	return rows


func _parser() -> bool:
	var ok := true
	var made := _parse(_good())
	var info: RoomInfo = made[0]
	ok = check(info != null and (made[1] as Array).is_empty(), "a row of E against the wall with track to spikes loads (%s)" % [made[1]]) and ok
	if info != null:
		ok = check(info.emitters.size() == 1 and info.platforms.is_empty() and info.movers.size() == 1, "it is an emitter and a mover, not a platform") and ok
		var path := info.emitters[0]
		ok = check(path.cells == 12 and path.direction == Vector2i.RIGHT and path.start_cells == Rect2i(1, 16, 4, 1), "track length and direction (%d, %s)" % [path.cells, path.direction]) and ok
	var rows := _good()
	rows[16] = "#" + "EEEE" + "-".repeat(12) + "." + ".".repeat(13) + "#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty() and "end of its track" in String(made[1][0]), "an open end is refused (%s)" % [made[1]]) and ok
	rows = _good()
	rows[16] = "." + "EEEE" + "-".repeat(12) + "^" + ".".repeat(12) + "#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty(), "no wall behind the machine is refused (%s)" % [made[1]]) and ok
	return ok


func _path() -> bool:
	var ok := true
	var path := EmitterPath.new("e", Rect2i(1, 16, 4, 1), Vector2i.RIGHT, 12, 60.0, 2.0)
	# 120 px at 60 px/s is 2 s: a trip of 120 ticks, a platform every 120.
	ok = check(path.life_ticks == 120 and path.every_ticks == 120 and path.slots == 1 and path.period() == 120, "one slot when the trip is as long as the gap (%d, %d, %d)" % [path.life_ticks, path.every_ticks, path.slots]) and ok
	ok = check(path.alive_at(0) and path.alive_at(119), "it is out for its whole trip") and ok
	ok = check(path.rect_at(60).position.x == 10.0 + 60.0, "half way along the track at half the trip (%s)" % path.rect_at(60)) and ok
	var fast := EmitterPath.new("f", Rect2i(1, 16, 4, 1), Vector2i.RIGHT, 12, 60.0, 0.5)
	ok = check(fast.slots == 4 and fast.period() == 120, "a shorter gap needs more slots (%d)" % fast.slots) and ok
	var count := func(e: EmitterPath, tick: int) -> int:
		var n := 0
		for body in e.body_count():
			if e.alive_at(tick, body):
				n += 1
		return n
	ok = check(count.call(fast, 0) == 4 and count.call(fast, 77) == 4, "a platform every half second, each lasting 2 s, is always four out") and ok
	var slow := EmitterPath.new("s", Rect2i(1, 16, 4, 1), Vector2i.RIGHT, 12, 60.0, 3.0)
	ok = check(slow.slots == 1 and slow.period() == 180 and count.call(slow, 119) == 1 and count.call(slow, 120) == 0 and count.call(slow, 179) == 0 and count.call(slow, 180) == 1, "with a gap longer than the trip, none is out for a while (%d)" % slow.period()) and ok
	ok = check(not slow.continuous_at(119) and slow.continuous_at(50), "the tick a platform breaks is not carried on") and ok
	ok = check(fast.rect_at(30, 0).position.x == fast.rect_at(0, 0).position.x + 30.0 and fast.rect_at(30, 1).position == fast.rect_at(0, 0).position, "a new platform starts where the first did") and ok
	var movers := Movers.new([path])
	ok = check(movers.size() == 1 and movers.alive(0, 5) and movers.step_of(0, 5) == Vector2(1.0, 0.0), "Movers sees the body and its step") and ok
	ok = check(movers.step_of(0, 119) == Vector2.ZERO, "the tick it breaks carries nobody") and ok
	return ok


func _sim() -> bool:
	var ok := true
	var cfg: MovementConfig = load("res://src/player/movement.tres")
	var path := EmitterPath.new("e", Rect2i(1, 10, 4, 1), Vector2i.RIGHT, 8, 60.0, 5.0)
	var movers := Movers.new([path])
	var floor_rects: Array = [Rect2(0, 180, 320, 10)]
	var s := MovementSim.State.new()
	s.position = Vector2(30.0, 100.0 - 5.0 - 0.0)
	s.grounded = true
	s.riding = 0
	var carried := true
	for tick in 40:
		MovementSim.step(cfg, s, floor_rects, 0.0, false, false, DT, movers, tick)
		carried = carried and s.riding == 0
	ok = check(carried and s.position.x > 30.0, "a rider is carried along (x %.1f)" % s.position.x) and ok
	# After the platform breaks nothing holds the rider up.
	for tick in range(40, 90):
		MovementSim.step(cfg, s, floor_rects, 0.0, false, false, DT, movers, tick)
	ok = check(s.riding == -1 and s.position.y > 100.0, "when it breaks, the rider falls (y %.1f)" % s.position.y) and ok
	return ok
