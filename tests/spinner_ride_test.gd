extends TestCase

## Safe blocks of a turning bar never kill. A body standing on a spinner's safe
## part (rooms 12 and 15), left alone for a whole turn or walking along it, is
## never crushed unless it touches a spiked part, or is squeezed against a
## static solid or another solid block (a true crush).

const DT := 1.0 / 60.0
const ROOMS: Array[String] = ["12", "15"]
const WALK_TICKS := 120
## One turn of the test bar, in ticks, so 4 ticks are 6 degrees.
const BAR_PERIOD := 240


func _initialize() -> void:
	watchdog(300.0)
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var graph := ReachGraph.new(data.rooms, cfg)
	for id in ROOMS:
		var info: RoomInfo = data.rooms[id]
		var rects: Array = graph.geometry_of(info).rects
		var movers := Movers.new(info.movers)
		_ride(cfg, id, rects, movers, info.spinners[0].period())
	_bar(cfg)
	finish("SPINNER RIDE")


## Every standing spot on a safe block at every 8th moment of one turn: stand
## still for a turn, then walk each way.
func _ride(cfg: MovementConfig, id: String, rects: Array, movers: Movers, period: int) -> void:
	var runs := 0
	var false_crushes := 0
	var first := ""
	for start in range(0, period, 8):
		for block in movers.rects(start):
			var spot := Vector2(block.get_center().x, block.position.y - MovementSim.HALF.y)
			if _inside_anything(spot, rects, movers, start):
				continue
			for input in [0.0, -1.0, 1.0]:
				var s := MovementSim.State.new()
				s.position = spot
				s.grounded = true
				s.riding = movers.body_under(block, start)
				var ticks := period if input == 0.0 else WALK_TICKS
				for t in ticks:
					var before := s.position
					MovementSim.step(cfg, s, rects, input, false, false, DT, movers, start + t)
					if s.crushed and not _on_hazard(s.position, movers, start + t + 1) and not _true_crush(s.position, rects, movers, start + t + 1) and not _under_ceiling(before, rects):
						false_crushes += 1
						if first.is_empty():
							first = "room %s tick %d+%d input %.0f at %s" % [id, start, t, input, s.position]
						break
					if s.crushed:
						break
				runs += 1
	check(runs > 0, "room %s: %d standing and walking runs" % [id, runs])
	check(false_crushes == 0, "room %s: no body is crushed on a safe block (%d of %d; first: %s)" % [id, false_crushes, runs, first])


func _inside_anything(position: Vector2, rects: Array, movers: Movers, tick: int) -> bool:
	for r: Rect2 in rects:
		if _overlaps(position, r):
			return true
	for r: Rect2 in movers.hazard_rects(tick):
		if _overlaps(position, r):
			return true
	var solid := movers.rects(tick)
	var count := 0
	for r: Rect2 in solid:
		if _overlaps(position, r):
			count += 1
	return count > 0


## Whether a static solid is within a few pixels over the head of a body at
## `position`: a bar that lifts it there squeezes it, which is a crush.
func _under_ceiling(position: Vector2, rects: Array) -> bool:
	var above := Rect2(position.x - 5.0, position.y - 5.0 - 6.0, 10.0, 6.0)
	for r: Rect2 in rects:
		if r.intersects(above):
			return true
	return false


func _on_hazard(position: Vector2, movers: Movers, tick: int) -> bool:
	for r: Rect2 in movers.hazard_rects(tick):
		if _overlaps(position, r):
			return true
	return false


## Inside a static solid, or inside a solid mover block.
func _true_crush(position: Vector2, rects: Array, movers: Movers, tick: int) -> bool:
	for r: Rect2 in rects:
		if _overlaps(position, r):
			return true
	for r: Rect2 in movers.rects(tick):
		if _overlaps(position, r):
			return true
	return false


func _overlaps(position: Vector2, block: Rect2) -> bool:
	return Rect2(position - MovementSim.HALF, MovementSim.HALF * 2.0).intersects(block)


## A plain 11 x 2 bar in an empty room (pivot at its middle, safe all over): a
## rider on it is carried round while the top face is within 60 degrees of flat,
## climbs it, and is pushed off, not killed, once it is steeper or upside down.
func _bar(cfg: MovementConfig) -> void:
	var bar := SpinnerPath.new("bar", Rect2i(10, 8, 11, 2), float(BAR_PERIOD) / 60.0, false, PackedStringArray())
	var movers := Movers.new([bar])
	var none: Array = []
	var top_row := movers.rects(0)
	var spot := Vector2(bar.pivot.x - 30.0, bar.rect_at(0, 0).position.y - 5.0)

	# Standing still on it through the first 60 degrees (40 ticks): always on the
	# bar, never crushed, and carried (the feet follow the bar's top).
	var s := _on_bar(movers, spot)
	var held := true
	var lost := -1
	for tick in 38:
		MovementSim.step(cfg, s, none, 0.0, false, false, DT, movers, tick)
		if not s.grounded or s.riding < 0 or s.crushed:
			held = false
			lost = tick
			break
	check(held, "a rider is carried through the first 60 degrees of the turn (lost at tick %d)" % lost)

	# Walking up the slope at 15 degrees: it moves on, and stays on the bar.
	s = _on_bar(movers, spot)
	for tick in 10:
		MovementSim.step(cfg, s, none, 0.0, false, false, DT, movers, tick)
	var from := s.position.x
	var grounded := 0
	for tick in range(10, 40):
		MovementSim.step(cfg, s, none, 1.0, false, true, DT, movers, tick)
		if s.grounded:
			grounded += 1
		if s.crushed:
			break
	check(not s.crushed and s.position.x - from > 20.0 and grounded >= 28, "it walks up a 15 to 60 degree slope (moved %.0f px, on the bar %d of 30 ticks)" % [s.position.x - from, grounded])

	# Walking down the slope: its feet stay on it.
	s = _on_bar(movers, Vector2(bar.pivot.x + 30.0, bar.rect_at(0, 10).position.y - 5.0))
	for tick in 10:
		MovementSim.step(cfg, s, none, 0.0, false, false, DT, movers, tick)
	grounded = 0
	for tick in range(10, 40):
		MovementSim.step(cfg, s, none, -1.0, false, false, DT, movers, tick)
		if s.grounded:
			grounded += 1
	check(not s.crushed and grounded >= 25, "it walks down the slope with its feet on it (on the bar %d of 30 ticks)" % grounded)

	# Past 60 degrees (and upside down) it is pushed off and falls; it is never
	# crushed, because nothing shuts the way.
	s = _on_bar(movers, spot)
	var crushed := false
	for tick in BAR_PERIOD / 2:
		MovementSim.step(cfg, s, none, 0.0, false, false, DT, movers, tick)
		crushed = crushed or s.crushed
	check(not crushed and s.riding < 0, "turned past 60 degrees it is pushed off, not crushed (riding %d)" % s.riding)
	var clear := Rect2(s.position - MovementSim.HALF, MovementSim.HALF * 2.0)
	var inside := false
	for r in movers.rects(BAR_PERIOD / 2):
		inside = inside or r.intersects(clear)
	check(not inside, "and it is clear of the bar afterwards")

	# A pit shuts every way out: the end of the bar that swings down onto the body
	# in it crushes it, since it cannot be pushed out.
	var floor_rects: Array = [
		Rect2(bar.pivot + Vector2(-100.0, 50.0), Vector2(200.0, 10.0)),
		Rect2(bar.pivot + Vector2(-12.0, 20.0), Vector2(2.0, 30.0)),
		Rect2(bar.pivot + Vector2(0.0, 20.0), Vector2(2.0, 30.0)),
	]
	s = MovementSim.State.new()
	s.position = bar.pivot + Vector2(-5.0, 45.0)
	s.grounded = true
	var squeezed := false
	for tick in BAR_PERIOD:
		MovementSim.step(cfg, s, floor_rects, 0.0, false, false, DT, movers, tick)
		squeezed = squeezed or s.crushed
	check(squeezed, "a body squeezed between the bar and a pit is crushed")


func _on_bar(movers: Movers, at: Vector2) -> MovementSim.State:
	var s := MovementSim.State.new()
	s.position = at
	s.grounded = true
	s.riding = movers.body_under(movers.rects(0)[0], 0)
	return s
