class_name Room
extends Node2D

signal exit_triggered(edge: String, dest_id: String)

var info
var _areas: Array[Area2D] = []


func build(room_info) -> void:
	info = room_info
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for cell_rect in info.solids:
		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		var pixel: Rect2 = Grid.cell_rect(cell_rect)
		shape.size = pixel.size
		shape_node.shape = shape
		shape_node.position = pixel.get_center()
		body.add_child(shape_node)
	add_child(body)
	for ex in info.exits:
		_add_exit(ex)
		_add_halo(ex)
	queue_redraw()


func set_exits_active(active: bool) -> void:
	for area in _areas:
		area.set_deferred("monitoring", active)
		area.set_deferred("monitorable", active)


func _draw() -> void:
	if info == null:
		return
	for cell_rect in info.solids:
		draw_rect(Grid.cell_rect(cell_rect), Color.WHITE, true)


func _add_exit(ex: Dictionary) -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = false
	area.monitorable = false
	var pixel: Rect2 = Grid.cell_rect(ex["rect"])
	match String(ex["edge"]):
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
	var edge := String(ex["edge"])
	var dest := String(ex["dest_id"])
	area.body_entered.connect(func(body: Node) -> void:
		if body is Player and not dest.is_empty():
			exit_triggered.emit(edge, dest)
	)
	add_child(area)
	_areas.append(area)


func _add_halo(ex: Dictionary) -> void:
	var pixel: Rect2 = Grid.cell_rect(ex["rect"])
	var halo := ExitHalo.new()
	match String(ex["edge"]):
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
