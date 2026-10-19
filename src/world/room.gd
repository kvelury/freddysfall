class_name Room
extends Node2D

var info: RoomInfo
## Whether touching a door changes rooms. Off while a transition is running.
var exits_active := false
var _hazard_rects: Array[Rect2] = []
var _pickups: Array[Pickup] = []
## The room's own solids, without any Imprint, for telling real floor from a
## platform that will break.
var _floor_rects: Array[Rect2] = []


## `flags` is what the player has already done (GameState.flags); things they
## have taken are left out.
func build(room_info: RoomInfo, flags := {}) -> void:
	info = room_info
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
	for ex in info.exits:
		_add_halo(ex)
	_floor_rects = world_rects()
	for def in info.entities:
		if not Entities.present(def, flags):
			continue
		var thing := Entities.create(def)
		thing.position = Grid.cell_center(def.cell)
		add_child(thing)
		if thing is Pickup:
			_pickups.append(thing)


func set_exits_active(active: bool) -> void:
	exits_active = active


## The door that a body at `body` (world pixels) is touching, or null.
func touched_door(body: Rect2) -> Door:
	if not exits_active:
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


## The pickups a body at `body` (world pixels) is touching.
func touched_pickups(body: Rect2) -> Array[Pickup]:
	var out: Array[Pickup] = []
	for pickup in _pickups:
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and pickup.rect().intersects(body):
			out.append(pickup)
	return out


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
## held up by the room's own floor (an Imprint breaks, and nothing would be
## under the player), not beside a hazard, and not in or next to a doorway.
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
## with.
func world_rects() -> Array[Rect2]:
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


func _add_halo(ex: Door) -> void:
	var pixel: Rect2 = Grid.cell_rect(ex.rect)
	var halo := ExitHalo.new()
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
