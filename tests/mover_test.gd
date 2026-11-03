extends TestCase

## What the solver may assume about every moving thing in the world (moving
## platforms, emitters, spinners), checked on every one the rooms place:
## - it repeats exactly after `period()` ticks: where each body is, whether it
##   is there and whether it moves smoothly on, so a solver may work out one
##   period and know them all;
## - no body is ever outside its `keep_out()`, the cells nothing else may use;
## - `ReachGraph.mover_space`, the box each mover's bodies stay in, holds every
##   body at every tick, so a jump whose path stays clear of it is the same jump
##   at every moment of the trip (see ReachGraph.reuse_margin).


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var graph := ReachGraph.new(data.rooms, cfg)
	var ids: Array = data.rooms.keys()
	ids.sort()
	var movers := 0
	var kinds := {}
	for id in ids:
		var info: RoomInfo = data.rooms[id]
		if info.movers.is_empty():
			continue
		var space: Array[Rect2] = graph.geometry_of(info).mover_space
		check(space.size() == info.movers.size(), "room %s: one space for each of its %d movers" % [id, info.movers.size()])
		for m in info.movers.size():
			movers += 1
			var mover := info.movers[m]
			kinds[mover.get_script().get_global_name()] = true
			_mover(String(id), mover, space[m] if m < space.size() else Rect2())
	check(movers > 0 and kinds.has("PlatformPath") and kinds.has("EmitterPath") and kinds.has("SpinnerPath"), "the world has every kind of mover to check (%d movers: %s)" % [movers, kinds.keys()])
	finish("MOVER")


func _mover(room_id: String, mover: Mover, space: Rect2) -> void:
	var period := mover.period()
	var keep := mover.keep_out()
	var repeats := true
	var inside := true
	var in_space := true
	for tick in range(-period, 2 * period + 1):
		for body in mover.body_count():
			var later := tick + period
			repeats = repeats and mover.rect_at(tick, body) == mover.rect_at(later, body) and mover.alive_at(tick, body) == mover.alive_at(later, body) and mover.continuous_at(tick, body) == mover.continuous_at(later, body)
			if not mover.alive_at(tick, body):
				continue
			var rect := mover.rect_at(tick, body)
			inside = inside and keep.encloses(rect)
			in_space = in_space and space.encloses(rect)
	var name := "room %s: %s (%d bodies, period %d)" % [room_id, mover.id, mover.body_count(), period]
	check(period > 0 and repeats, name + " repeats exactly after its period")
	check(inside, name + " never leaves its keep-out")
	check(in_space, name + " stays in the space the solver gives it")
