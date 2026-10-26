class_name Room
extends Node2D

var info: RoomInfo
## Whether touching a door changes rooms. Off while a transition is running.
var exits_active := false
var _hazard_rects: Array[Rect2] = []
## Everything the player can touch: pickups, tokens, 3TMs and save machines.
var _things: Array[Node2D] = []
## The room's own solids, without any Imprint, for telling real floor from a
## platform that will break.
var _floor_rects: Array[Rect2] = []
## Whether the room's exit rule is unmet, so its doors are blocked.
var locked := false
var _blocks: Array[DoorBlock] = []
var _halos: Array[ExitHalo] = []
var _door_override := false
var _flags := {}
## The room's clock for its moving platforms, in physics ticks since it was
## built. Each one starts at the end it is drawn at, waiting.
var tick := 0
## The moving platforms as a body sees them, in world pixels.
var movers := Movers.new()
var _platforms: Array[MovingPlatform] = []

## Emitted when the exit rule becomes met and the doors open.
signal exits_opened


## `flags` is what the player has already done (GameState.flags); things they
## have taken are left out. `fills` is how full each 3TM is, by id.
func build(room_info: RoomInfo, flags := {}, fills := {}, door_override := false) -> void:
	info = room_info
	_flags = flags
	# The platforms move before the player steps, so the player is carried to
	# where they are this tick.
	process_priority = -1
	_door_override = door_override
	locked = not door_override and not ExitRules.met(info, flags)
	# One drawable chunk per screen. Godot culls a chunk whose rect is
	# outside the camera, so a long room costs the same as the screens in view.
	var screens: Vector2i = info.screens
	for cell in info.hazards:
		var pixel := Grid.cell_rect(Rect2i(cell, Vector2i.ONE))
		_hazard_rects.append(Rect2(pixel.position + position, pixel.size))
	for sy in screens.y:
		for sx in screens.x:
			var local_rects := _rects_in_screen(info.solids, sx, sy)
			var local_hazards := _hazards_in_screen(sx, sy)
			if local_rects.is_empty() and local_hazards.is_empty():
				continue
			var chunk := RoomChunk.new()
			chunk.name = "Chunk_%d_%d" % [sx, sy]
			chunk.position = Vector2(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y) * float(Grid.CELL)
			chunk.rects = local_rects
			chunk.hazards = local_hazards
			add_child(chunk)
	_floor_rects = _solid_rects()
	for ex in info.exits:
		if locked:
			_add_block(ex)
		else:
			_add_halo(ex)
	movers = Movers.new(info.platforms, position)
	for path in info.platforms:
		var platform := MovingPlatform.new(path)
		add_child(platform)
		platform.reset_physics_interpolation()
		_platforms.append(platform)
	for def in info.entities:
		if def.type == "platform" or not Entities.present(def, flags):
			continue
		var thing := Entities.create(def, fills)
		thing.position = Grid.cell_center(def.cell)
		add_child(thing)
		if thing is Pickup or thing is Token or thing is HealthPip or thing is TokenMachine or thing is SaveMachine:
			_things.append(thing)


func _physics_process(_delta: float) -> void:
	if _platforms.is_empty():
		return
	tick += 1
	for platform in _platforms:
		platform.move_to(tick)


## The moving platforms where they are now, in world pixels.
func mover_rects() -> Array[Rect2]:
	return movers.rects(tick)


func set_exits_active(active: bool) -> void:
	exits_active = active


## The door that a body at `body` (world pixels) is touching, or null.
func touched_door(body: Rect2) -> Door:
	if not exits_active or locked:
		return null
	for door in info.exits:
		var trigger := door.trigger_rect()
		if Rect2(trigger.position + position, trigger.size).intersects(body):
			return door
	return null


## Spikes and door triggers as pixel rects in world space, for paths that
## have to know what kills and what leaves the room.
func hazard_world_rects() -> Array[Rect2]:
	return _hazard_rects


func door_world_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for door in info.exits:
		var trigger := door.trigger_rect()
		out.append(Rect2(trigger.position + position, trigger.size))
	return out


## The pickups, tokens, health pips, 3TMs and save machines a body at `body` (world pixels)
## is touching. A token or 3TM the body has left forgets that it already told
## the player something.
func touched_things(body: Rect2) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for thing in _things:
		if not is_instance_valid(thing) or thing.is_queued_for_deletion():
			continue
		if thing.rect().intersects(body):
			out.append(thing)
		elif thing is Token or thing is TokenMachine:
			thing.noted = false
	return out


## The save machine that a body at `body` (world pixels) is inside, or null. A
## body put there by a respawn or a load has to come out of it, not walk in.
func save_machine_holding(body: Rect2) -> SaveMachine:
	for thing in _things:
		if thing is SaveMachine and thing.footprint_rect().intersects(body):
			return thing
	return null


## Whether a body at `body` (world pixels) is touching a hazard.
func touches_hazard(body: Rect2) -> bool:
	for rect in _hazard_rects:
		if rect.intersects(body):
			return true
	return false


## Whether a body that has left the room's outline by more than a screen's
## edge margin has fallen out of the world.
func is_outside(world_point: Vector2) -> bool:
	return not Rect2(position, info.pixel_size).grow(60.0).has_point(world_point)


## Whether a body resting at `body` is somewhere to come back to after dying:
## held up by the room's own floor (an Imprint breaks and a moving platform
## moves, and nothing would be under the player), not beside a hazard, and not
## in or next to a doorway.
func is_safe_spot(body: Rect2) -> bool:
	if not MovementSim.standing(body.get_center(), _floor_rects):
		return false
	var cell := float(Grid.CELL)
	var near := body.grow_individual(cell, 0.0, cell, 0.0)
	for rect in _hazard_rects:
		if rect.intersects(near):
			return false
	for door in info.exits:
		var trigger := door.trigger_rect()
		var zone := Rect2(trigger.position + position, trigger.size).grow(cell * 2.0)
		if zone.intersects(body):
			return false
	return true


## The room's solids as pixel rects in world space, for the player to collide
## with. While the doors are blocked the blocks are solid too.
func world_rects() -> Array[Rect2]:
	var out := _solid_rects()
	for block in _blocks:
		out.append(Rect2(block.position + position, block.size))
	return out


## Opens the doors if the exit rule is now met: the blocks shatter and the
## halos appear. Says whether it did. `flags` is what the player has done.
func recheck_exits(flags: Dictionary) -> bool:
	_flags = flags
	if not locked or not (_door_override or ExitRules.met(info, flags)):
		return false
	_refresh_doors(false)
	return true


## Runtime-only bypass; real progression requirements remain pure and unchanged.
func set_door_override(on: bool, flags: Dictionary) -> void:
	_door_override = on
	_flags = flags
	_refresh_doors(not on and not ExitRules.met(info, flags))


func _refresh_doors(want_locked: bool) -> void:
	if locked == want_locked:
		return
	locked = want_locked
	for block in _blocks:
		if not want_locked:
			var burst := Shatter.new()
			burst.position = block.position + block.size * 0.5
			add_child(burst)
		block.queue_free()
	_blocks.clear()
	for halo in _halos:
		halo.queue_free()
	_halos.clear()
	for ex in info.exits:
		if locked:
			_add_block(ex)
		else:
			_add_halo(ex)
	exits_opened.emit()


func _solid_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for cell_rect in info.solids:
		var pixel := Grid.cell_rect(cell_rect)
		out.append(Rect2(pixel.position + position, pixel.size))
	return out


func _hazards_in_screen(sx: int, sy: int) -> Array[Vector2i]:
	var screen := Rect2i(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y, Grid.SCREEN_CELLS.x, Grid.SCREEN_CELLS.y)
	var out: Array[Vector2i] = []
	for cell in info.hazards:
		if screen.has_point(cell):
			out.append(cell - screen.position)
	return out


func _rects_in_screen(solids: Array[Rect2i], sx: int, sy: int) -> Array[Rect2i]:
	var screen := Rect2i(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y, Grid.SCREEN_CELLS.x, Grid.SCREEN_CELLS.y)
	var out: Array[Rect2i] = []
	for cell_rect in solids:
		if not screen.intersects(cell_rect):
			continue
		var clipped: Rect2i = screen.intersection(cell_rect)
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		out.append(Rect2i(clipped.position - screen.position, clipped.size))
	return out


func _add_block(ex: Door) -> void:
	var block := DoorBlock.new()
	block.size = Grid.cell_rect(ex.rect).size
	block.position = Grid.cell_rect(ex.rect).position
	block.z_index = 1
	add_child(block)
	_blocks.append(block)


func _add_halo(ex: Door) -> void:
	var pixel: Rect2 = Grid.cell_rect(ex.rect)
	var halo := ExitHalo.new()
	_halos.append(halo)
	match ex.edge:
		"right":
			halo.position = Vector2(pixel.end.x, pixel.get_center().y)
			halo.direction = Vector2.LEFT
		"left":
			halo.position = Vector2(pixel.position.x, pixel.get_center().y)
			halo.direction = Vector2.RIGHT
		"up":
			halo.position = Vector2(pixel.get_center().x, pixel.position.y)
			halo.direction = Vector2.DOWN
		"down":
			halo.position = Vector2(pixel.get_center().x, pixel.end.y)
			halo.direction = Vector2.UP
	halo.z_index = 1
	add_child(halo)


class RoomChunk extends Node2D:
	var rects: Array[Rect2i] = []
	var hazards: Array[Vector2i] = []

	func _draw() -> void:
		for cell_rect in rects:
			draw_rect(Grid.cell_rect(cell_rect), Color.WHITE, true)
		# Spikes: a row of teeth, so a hazard reads as sharp and not as a block.
		for cell in hazards:
			var origin := Grid.cell_to_world(cell)
			for tooth in 2:
				var left := origin.x + float(tooth) * 5.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(left, origin.y + 10.0),
					Vector2(left + 2.5, origin.y + 3.0),
					Vector2(left + 5.0, origin.y + 10.0),
				]), Color.WHITE)


## A shaded block that fills a doorway while the room's exit rule is unmet:
## a solid frame around a checker, so it reads as a barrier and not as wall.
class DoorBlock extends Node2D:
	var size := Vector2(10, 10)

	func _init() -> void:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		for y in h:
			for x in w:
				var frame := x == 0 or y == 0 or x == w - 1 or y == h - 1
				if frame or (x + y) % 2 == 0:
					draw_rect(Rect2(x, y, 1, 1), Color.WHITE)
