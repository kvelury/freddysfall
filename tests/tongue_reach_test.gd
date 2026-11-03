extends TestCase

## The tongue's reach is one function. A wall a few cells away is hit, a wall
## past the tongue's length is not, and a solid in front of a wall is what stops
## the tip.


func _initialize() -> void:
	var info := RoomInfo.new()
	info.id = "t"
	info.cell_size = Vector2i(16, 8)
	for y in 8:
		var row := ""
		for x in 16:
			row += "#" if y == 7 or x == 0 or x == 15 else "."
		info.rows.append(row)
	info.register_breakable("near", [Vector2i(4, 3)])
	info.register_breakable("far", [Vector2i(12, 3)])
	var center := Vector2(1.5 * Grid.CELL, 3.5 * Grid.CELL)
	var dir := Vector2(1.0, 0.0)
	var mouth := TongueReach.mouth(center, dir)
	var near := TongueReach.first_hit(info, mouth, dir, 50.0)
	check(near["wall"] == "near" and near["solid"], "a tongue of 50 px hits the wall four cells away")
	var short := TongueReach.first_hit(info, mouth, dir, 15.0)
	check(short["wall"] == "" and not short["solid"], "a tongue of 15 px does not reach it")
	info.rows[3] = info.rows[3].substr(0, 3) + "#" + info.rows[3].substr(4)
	var stopped := TongueReach.first_hit(info, mouth, dir, 50.0)
	check(stopped["wall"] == "" and stopped["solid"], "a solid in front of the wall stops the tongue, and the wall is not hit")
	var up := Vector2(0.0, -1.0)
	info.register_breakable("above", [Vector2i(1, 1)])
	var risen := TongueReach.first_hit(info, TongueReach.mouth(center, up), up, 50.0)
	check(risen["wall"] == "above", "lashing up hits the wall above")
	finish("TONGUE REACH")
