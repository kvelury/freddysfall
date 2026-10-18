class_name Room
extends Node2D

signal exit_triggered(edge: String, dest_id: String, dest_rect: Rect2i)

var info: RoomInfo
var _areas: Array[Area2D] = []


func build(room_info: RoomInfo) -> void:
	info = room_info
	# One drawable chunk per screen. Godot culls a chunk whose rect is
	# outside the camera, so a long room costs the same as the screens in view.
	var screens: Vector2i = info.screens
	for sy in screens.y:
		for sx in screens.x:
			var local_rects := _rects_in_screen(info.solids, sx, sy)
			if local_rects.is_empty():
				continue
			var chunk := RoomChunk.new()
			chunk.name = "Chunk_%d_%d" % [sx, sy]
			chunk.position = Vector2(sx * Grid.SCREEN_CELLS.x, sy * Grid.SCREEN_CELLS.y) * float(Grid.CELL)
			chunk.rects = local_rects
			chunk.setup_collision()
			add_child(chunk)
	for ex in info.exits:
		_add_exit(ex)
		_add_halo(ex)


func set_exits_active(active: bool) -> void:
	for area in _areas:
		area.set_deferred("monitoring", active)
		area.set_deferred("monitorable", active)


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


func _add_exit(ex: Door) -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = false
	area.monitorable = false
	var pixel: Rect2 = Grid.cell_rect(ex.rect)
	match ex.edge:
		"right":
			pixel.position.x -= 4.0
			pixel.size.x += 4.0
		"left":
			pixel.size.x += 4.0
		"up":
			pixel.size.y += 4.0
		"down":
			pixel.position.y -= 4.0
			pixel.size.y += 4.0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = pixel.size
	shape_node.shape = shape
	shape_node.position = pixel.get_center()
	area.add_child(shape_node)
	var edge := ex.edge
	var dest := ex.dest_id
	var dest_rect := ex.dest_rect
	area.body_entered.connect(func(body: Node) -> void:
		if body is Player and not dest.is_empty():
			exit_triggered.emit(edge, dest, dest_rect)
	)
	add_child(area)
	_areas.append(area)


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

	func setup_collision() -> void:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for cell_rect in rects:
			var shape_node := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			var pixel := Grid.cell_rect(cell_rect)
			shape.size = pixel.size
			shape_node.shape = shape
			shape_node.position = pixel.get_center()
			body.add_child(shape_node)
		add_child(body)

	func _draw() -> void:
		for cell_rect in rects:
			draw_rect(Grid.cell_rect(cell_rect), Color.WHITE, true)
