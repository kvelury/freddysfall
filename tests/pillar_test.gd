extends TestCase

## Breakable emitters (pillars): a rectangle of the glyph more than one row tall,
## running side to side along its bottom row's track, whose bodies Tongue Lash
## breaks. The parser's rules, the movers' broken bodies (gone for the rest of
## their trip, whole when their slot comes round again), and play: a lash breaks
## one in wall-strength hits, and one not lashed pushes the player along.

const FIXTURE := "res://tests/fixtures/worlds/pillars/"
const LEGEND := "legend:\n  E = emitter id=p1 speed=30 every=4 breakable=true\n---\n"


func _initialize() -> void:
	watchdog(120.0)
	_run()


func _run() -> void:
	var ok := true
	ok = _parser() and ok
	ok = _movers() and ok
	ok = await _play() and ok
	finish("PILLAR", ok)


## 32 x 18: a floor, a 2 x 3 pillar machine on the right wall, its track on the
## bottom row running left to wall spikes in column 1.
static func _good() -> Array[String]:
	var rows: Array[String] = []
	for y in 18:
		rows.append("#" + ".".repeat(30) + "#")
	rows[0] = "#".repeat(32)
	rows[17] = "#".repeat(32)
	rows[14] = "#^" + ".".repeat(27) + "EE#"
	rows[15] = "#^" + ".".repeat(27) + "EE#"
	rows[16] = "#^" + "-".repeat(27) + "EE#"
	return rows


static func _parse(rows: Array[String], legend := LEGEND) -> Array:
	var errors: Array[String] = []
	var info := RoomParser.parse_room("t", Vector2i.ZERO, legend + "\n".join(rows), errors)
	return [info, errors]


func _parser() -> bool:
	var ok := true
	var made := _parse(_good())
	var info: RoomInfo = made[0]
	ok = check(info != null and (made[1] as Array).is_empty(), "a 2 x 3 pillar against the wall, track on its bottom row to spikes, loads (%s)" % [made[1]]) and ok
	if info != null and info.emitters.size() == 1:
		var path := info.emitters[0]
		ok = check(path.start_cells == Rect2i(29, 14, 2, 3) and path.direction == Vector2i.LEFT and path.cells == 27 and path.breakable, "its rectangle, direction, track and breakable (%s, %s, %d)" % [path.start_cells, path.direction, path.cells]) and ok
		ok = check(path.rect_at(0).size == Vector2(20, 30) and path.swept_cells() == Rect2i(2, 14, 29, 3) and path.band_cells() == Rect2i(2, 13, 29, 1), "its body is 20 x 30 px and it sweeps all three rows") and ok
	# Something over the track, in the pillar's way.
	var rows := _good()
	rows[14] = "#^" + ".".repeat(10) + "#" + ".".repeat(16) + "EE#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty() and "open air everywhere it goes" in String(made[1][0]), "a block over the track is refused (%s)" % [made[1]]) and ok
	# The upper rows must also end on spikes or solid.
	rows = _good()
	rows[14] = "#." + ".".repeat(27) + "EE#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty() and "end of its track" in String(made[1][0]), "an open end on an upper row is refused (%s)" % [made[1]]) and ok
	# A gap in the rectangle.
	rows = _good()
	rows[15] = "#^" + ".".repeat(27) + "E.#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty() and "gap" in String(made[1][0]), "a rectangle with a gap is refused (%s)" % [made[1]]) and ok
	# A tall emitter going up and down.
	rows = _good()
	rows[14] = "#" + ".".repeat(28) + "EE#"
	rows[15] = "#" + ".".repeat(28) + "EE#"
	rows[16] = "#" + ".".repeat(28) + "EE#"
	for y in range(5, 14):
		rows[y] = "#" + ".".repeat(28) + "||#"
	rows[4] = "#" + ".".repeat(28) + "^^#"
	made = _parse(rows)
	ok = check(not (made[1] as Array).is_empty() and "side to side" in String(made[1][0]), "a tall emitter with up-and-down track is refused (%s)" % [made[1]]) and ok
	# breakable= takes only true.
	made = _parse(_good(), "legend:\n  E = emitter id=p1 speed=30 every=4 breakable=yes\n---\n")
	ok = check(not (made[1] as Array).is_empty() and "breakable=" in String(made[1][0]), "breakable=yes is refused (%s)" % [made[1]]) and ok
	# A one-row moving platform is still one row only.
	rows = _good()
	rows[14] = "#^" + ".".repeat(27) + "LL#"
	rows[15] = "#^" + ".".repeat(27) + "LL#"
	rows[16] = "#^" + "-".repeat(27) + "LL#"
	made = _parse(rows, "legend:\n  L = platform id=l1 speed=30\n---\n")
	ok = check(not (made[1] as Array).is_empty() and "more than one row" in String(made[1][0]), "a moving platform drawn on three rows is still refused (%s)" % [made[1]]) and ok
	return ok


func _movers() -> bool:
	var ok := true
	# 270 px at 30 px/s: a trip of 540 ticks, one every 240, so three slots.
	var path := EmitterPath.new("p", Rect2i(29, 14, 2, 3), Vector2i.LEFT, 27, 30.0, 4.0, true)
	ok = check(path.slots == 3 and path.period() == 720, "three slots, back to the start every 720 ticks (%d, %d)" % [path.slots, path.period()]) and ok
	var movers := Movers.new([path])
	var box := movers.rect(0, 100).grow(-2.0)
	ok = check(movers.pillar_at(box, 100) == 0, "a box on the first pillar finds it") and ok
	movers.break_body(0, 100)
	ok = check(not movers.alive(0, 100) and not movers.alive(0, 539) and movers.pillar_at(box, 100) == -1, "broken, it is gone for the rest of its trip") and ok
	ok = check(movers.alive(1, 300) and movers.rects(300).size() == 1, "the next slot's pillar is untouched") and ok
	ok = check(movers.alive(0, 720) and movers.rect(0, 720) == movers.rect(0, 0), "and it is back, whole, when its slot comes out again") and ok
	ok = check(movers.alive(0, 1440 + 100), "and the trip after that too: a break is forgotten") and ok
	var plain := Movers.new([EmitterPath.new("q", Rect2i(29, 14, 2, 3), Vector2i.LEFT, 27, 30.0, 4.0)])
	ok = check(plain.pillar_at(plain.rect(0, 100).grow(-2.0), 100) == -1, "an emitter that is not breakable has no pillar to hit") and ok
	return ok


func _play() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	root.get_node("WorldData").load_from(FIXTURE + "world.json", FIXTURE + "rooms/")
	state.reset()
	var world: Node = await boot_world("1")
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	tongue.scripted = true
	tongue.scripted_held = false
	state.abilities.tongue_unlocked = true
	var room: Room = world.current
	_put(world, Vector2i(20, 16))
	# Wait for the first pillar to come within the tongue's reach.
	await until(func() -> bool: return room.movers.rect(0, room.tick).position.x - room.position.x < 255.0, 200)
	var lashes := 0
	var broke := -1
	for i in 120:
		if not tongue.active and tongue.cooldown_left <= 0.0 and room.movers.alive(0, room.tick):
			if tongue.lash():
				lashes += 1
		await physics_frame
		if not room.movers.alive(0, room.tick):
			broke = i
			break
	ok = check(broke >= 0 and lashes == root.get_node("DevSession").wall_strength(), "a pillar breaks after %d lashes (%d)" % [root.get_node("DevSession").wall_strength(), lashes]) and ok
	await physics_frame
	ok = check(not room.movers.alive(0, room.tick) and room.movers.rects(room.tick).size() == (1 if room.movers.alive(1, room.tick) else 0) + (1 if room.movers.alive(2, room.tick) else 0), "and nothing of it is solid any more (tick %d)" % room.tick) and ok
	# A hit on the next pillar, then the room built again: whole.
	room.tick = 300
	var body := room.movers.pillar_at(room.movers.rect(1, 300).grow(-2.0), 300)
	ok = check(body == 1 and not room.hit_pillar(body, 2), "one hit does not break the next pillar") and ok
	ok = check(room.hit_pillar(body, 2) and not room.movers.alive(1, 300), "the second does") and ok
	# A pillar not lashed pushes him along the floor.
	world.warp_to("1")
	await physics_frame
	room = world.current
	tongue.clear()
	_put(world, Vector2i(20, 16))
	var start_x := player.global_position.x
	var pushed := false
	for i in 200:
		await physics_frame
		if player.global_position.x < start_x - 15.0:
			pushed = true
			break
	ok = check(pushed, "a pillar that is not lashed pushes him the way it goes") and ok
	world.queue_free()
	return ok


func _put(world: Node, cell: Vector2i) -> void:
	var player: Player = world.get_node("Player")
	var tongue: Node = world.get_node("TongueLash")
	tongue.clear()
	player.scripted_x = 0.0
	player.place(world.current.position + Grid.cell_center(cell), world.current.world_rects())
	player.facing = 1
