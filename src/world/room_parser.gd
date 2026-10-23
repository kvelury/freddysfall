class_name RoomParser
extends RefCounted

## Turns room text into RoomInfo and pairs the doors. Nothing here touches the
## disk or the scene tree, so tests can build a whole world from strings.
## Problems are appended to `errors`; loading never stops at the first one.

## A bad drawing tends to repeat one mistake along a whole wall. Past this
## many per room and kind, the rest are counted instead of listed.
const MAX_PER_KIND := 5
## A room file may start with a header, ended by a line holding only this.
const HEADER_END := "---"
const LEGEND := "legend:"
const EXITS := "exits:"
const TRAP := "trap:"
## What `trap:` may say.
const TRAP_ALLOWED := "allowed"


## entries: [{"id": String, "grid_pos": Vector2i, "text": String}]
## Returns {"rooms": {id: RoomInfo}, "by_pos": {Vector2i: id}}.
static func build(entries: Array, start_room: String, errors: Array[String]) -> Dictionary:
	var rooms := {}
	var by_pos := {}
	var order: Array[RoomInfo] = []
	for entry in entries:
		if not is_valid_id(String(entry["id"])):
			errors.append("Room id \"%s\" is not allowed; a room id is a number (\"4\") or s and a number (\"s1\", a save room)" % String(entry["id"]))
		var info := parse_room(String(entry["id"]), Vector2i(entry["grid_pos"]), String(entry["text"]), errors)
		if rooms.has(info.id):
			errors.append("Room id %s is listed twice" % info.id)
			continue
		rooms[info.id] = info
		for cell in info.occupied_cells():
			if by_pos.has(cell):
				errors.append("Room %s overlaps %s at screen %s" % [info.id, String(by_pos[cell]), cell])
			else:
				by_pos[cell] = info.id
		order.append(info)
	var entity_rooms := {}
	for info in order:
		for def in info.entities:
			if entity_rooms.has(def.id):
				errors.append("%s id \"%s\" is used in room %s and room %s; an id names one thing in the whole world" % [def.type.capitalize(), def.id, entity_rooms[def.id], info.id])
			else:
				entity_rooms[def.id] = info.id
	for info in order:
		info.exits = _parse_exits(info, by_pos, errors)
	_link_exits(order, rooms, errors)
	for info in order:
		_seal_dead_ends(info)
		info.solids = merge_solids(info.rows)
	if not rooms.has(start_room):
		errors.append("Start room \"%s\" is not in the world" % start_room)
	elif not (rooms[start_room] as RoomInfo).has_spawn:
		errors.append("Start room %s has no %s for the player to start on" % [start_room, Tiles.SPAWN])
	return {"rooms": rooms, "by_pos": by_pos}


## Whether `id` is a number, or `s` and a number for a save room.
static func is_valid_id(id: String) -> bool:
	var digits := id.substr(1) if RoomInfo.is_save_id(id) else id
	return not digits.is_empty() and digits.is_valid_int() and not digits.begins_with("-") and not digits.begins_with("+")


static func parse_room(id: String, grid_pos: Vector2i, text: String, errors: Array[String]) -> RoomInfo:
	var info := RoomInfo.new()
	info.id = id
	info.grid_pos = grid_pos
	var parts := _split_header(text, id, errors)
	var header := _read_header(parts["header"], id, errors)
	info.legend = header["legend"]
	info.exit_rule = header["exits"]
	info.traps_allowed = header["trap"]
	info.rows = _read_rows(String(parts["grid"]), id, errors)
	_apply_size(info)
	_scan_cells(info, errors)
	_check_save_things(info, errors)
	var problem := ExitRules.problem(info.exit_rule, info)
	if not problem.is_empty():
		errors.append("Room %s: %s" % [id, problem])
	return info


static func _read_rows(text: String, room_id: String, errors: Array[String]) -> Array[String]:
	var rows: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.replace("\r", "")
		if line.is_empty():
			continue
		rows.append(line)
	if rows.is_empty():
		errors.append("Room %s is empty" % room_id)
		return rows
	var width := rows[0].length()
	var height := rows.size()
	var screen := Grid.SCREEN_CELLS
	if width % screen.x != 0 or height % screen.y != 0:
		errors.append("Room %s is %d x %d cells; size must be a whole number of %d x %d screens" % [room_id, width, height, screen.x, screen.y])
	for y in rows.size():
		if rows[y].length() != width:
			errors.append("Room %s row %d has width %d, expected %d" % [room_id, y, rows[y].length(), width])
	return rows


static func _apply_size(info: RoomInfo) -> void:
	if info.rows.is_empty():
		info.cell_size = Grid.SCREEN_CELLS
	else:
		info.cell_size = Vector2i(info.rows[0].length(), info.rows.size())
	var screen := Grid.SCREEN_CELLS
	info.screens = Vector2i(maxi(1, int(info.cell_size.x / screen.x)), maxi(1, int(info.cell_size.y / screen.y)))
	info.pixel_size = Vector2(info.cell_size) * float(Grid.CELL)
	# Imprint platforms must fit inside the whole room, not just the screen
	# the camera happens to be showing.
	info.bounds_cells = Rect2i(Vector2i.ZERO, info.cell_size)


## One pass over the grid: finds the spawn and the no-imprint cells, and
## reports glyphs that mean nothing and outer-wall cells that are not wall.
static func _scan_cells(info: RoomInfo, errors: Array[String]) -> void:
	var rows := info.rows
	if rows.is_empty():
		return
	var width := rows[0].length()
	var height := rows.size()
	var unknown: Array[String] = []
	var open_edge: Array[String] = []
	var placements := {}
	for y in height:
		var row := rows[y]
		for x in mini(width, row.length()):
			var glyph := row[x]
			var on_edge := x == 0 or y == 0 or x == width - 1 or y == height - 1
			if info.legend.has(glyph):
				if not placements.has(glyph):
					placements[glyph] = []
				placements[glyph].append(Vector2i(x, y))
				if on_edge:
					open_edge.append("Room %s edge cell %d,%d is '%s'; the outer wall must be %s or %s" % [info.id, x, y, glyph, Tiles.SOLID, Tiles.EXIT])
				continue
			if not Tiles.is_known(glyph):
				unknown.append("Room %s cell %d,%d is '%s', which is not a known glyph" % [info.id, x, y, glyph])
				continue
			if Tiles.has_flag(glyph, "spawn") and not info.has_spawn:
				info.has_spawn = true
				info.spawn_cell = Vector2i(x, y)
			if Tiles.has_flag(glyph, "no_imprint"):
				info.no_imprint.append(Vector2i(x, y))
			if Tiles.has_flag(glyph, "hazard"):
				info.hazards.append(Vector2i(x, y))
			if on_edge and not Tiles.is_wall_glyph(glyph):
				open_edge.append("Room %s edge cell %d,%d is '%s'; the outer wall must be %s or %s" % [info.id, x, y, glyph, Tiles.SOLID, Tiles.EXIT])
	_place_entities(info, placements, errors)
	_append_capped(errors, unknown)
	_append_capped(errors, open_edge)


## Each legend glyph stands for exactly one thing, so it has to appear on the
## grid exactly once. Where it does is that thing's cell.
static func _place_entities(info: RoomInfo, placements: Dictionary, errors: Array[String]) -> void:
	for glyph in info.legend:
		var def: EntityDef = info.legend[glyph]
		var cells: Array = placements.get(glyph, [])
		if cells.is_empty():
			errors.append("Room %s: legend glyph '%s' (%s %s) is never drawn in the room" % [info.id, glyph, def.type, def.id])
		elif cells.size() > 1:
			errors.append("Room %s: legend glyph '%s' (%s %s) is drawn %d times, at %s and elsewhere; each one needs its own glyph and id" % [info.id, glyph, def.type, def.id, cells.size(), cells[0]])
		else:
			def.cell = cells[0]
			if def.type == "machine" or def.type == "save":
				var problem := _machine_space(info, def)
				if def.type == "save" and problem.is_empty():
					problem = _save_floor(info, def)
				if not problem.is_empty():
					errors.append(problem)
			info.entities.append(def)


## A save room has exactly one save machine, and no other room has one.
static func _check_save_things(info: RoomInfo, errors: Array[String]) -> void:
	var saves := info.entities.filter(func(def: EntityDef) -> bool: return def.type == "save").size()
	if info.is_save_room() and saves != 1:
		errors.append("Room %s is a save room (its id starts with s) and needs exactly one save machine in its legend, but has %d" % [info.id, saves])
	elif not info.is_save_room() and saves > 0:
		errors.append("Room %s has a save machine, but only a room whose id is s and a number (like s1) can be a save room" % info.id)


## A save machine's glyph is where the player comes back, so the cell under it
## must be solid for them to stand on. Returns a sentence, or "".
static func _save_floor(info: RoomInfo, def: EntityDef) -> String:
	var below := def.cell + Vector2i(0, 1)
	if below.y >= info.rows.size() or below.x >= info.rows[below.y].length() or not Tiles.has_flag(info.rows[below.y][below.x], "solid"):
		return "Room %s: save machine %s at %s needs solid floor in the cell under it (%d,%d), for the player to stand on" % [info.id, def.id, def.cell, below.x, below.y]
	return ""


## A 3TM or a save machine fills 3 x 3 cells, and they have to be open air: not
## wall, a door, spikes, or another thing. Returns the first problem as a
## sentence, or "".
static func _machine_space(info: RoomInfo, def: EntityDef) -> String:
	var space := TokenMachine.footprint(def.cell)
	var label := "3TM" if def.type == "machine" else "save machine"
	for y in range(space.position.y, space.end.y):
		for x in range(space.position.x, space.end.x):
			var glyph := ""
			if y >= 0 and y < info.rows.size() and x >= 0 and x < info.rows[y].length():
				glyph = info.rows[y][x]
			if glyph != Tiles.EMPTY and glyph != Tiles.NO_IMPRINT and glyph != def.glyph:
				return "Room %s: %s %s at %s needs open air in the 3 x 3 cells it fills (%d,%d to %d,%d), but cell %d,%d is '%s'" % [info.id, label, def.id, def.cell, space.position.x, space.position.y, space.end.x - 1, space.end.y - 1, x, y, glyph if not glyph.is_empty() else "outside the room"]
	return ""


## A room file is the grid, or a header, a line of three dashes, and the
## grid. Returns {"header": [[line number, text], ...], "grid": String}.
static func _split_header(text: String, room_id: String, errors: Array[String]) -> Dictionary:
	var lines := text.split("\n")
	var divider := -1
	for i in lines.size():
		if lines[i].strip_edges() == HEADER_END:
			divider = i
			break
	var header: Array = []
	if divider == -1:
		for i in lines.size():
			var first := lines[i].strip_edges()
			if first.begins_with(LEGEND) or first.begins_with(EXITS) or first.begins_with(TRAP):
				errors.append("Room %s line %d: a header needs a line of %s between it and the room, so the room cannot be read" % [room_id, i + 1, HEADER_END])
				return {"header": header, "grid": ""}
		return {"header": header, "grid": text}
	for i in divider:
		header.append([i + 1, lines[i]])
	return {"header": header, "grid": "\n".join(lines.slice(divider + 1))}


## Reads the header: `legend:` and its lines, `G = kind id=name key=value ...`,
## into glyph -> EntityDef (without a cell yet), `exits: rule`, and
## `trap: allowed`. Returns {"legend": {...}, "exits": String, "trap": bool}.
static func _read_header(header: Array, room_id: String, errors: Array[String]) -> Dictionary:
	var legend := {}
	var rule := ExitRules.OPEN
	var in_legend := false
	var rule_line := 0
	var trap_line := 0
	var trap := false
	for item in header:
		var number: int = item[0]
		var line := String(item[1]).replace("\t", " ").strip_edges()
		if line.is_empty():
			continue
		if line.begins_with(EXITS):
			if rule_line != 0:
				errors.append("Room %s line %d: exits: is given twice (first on line %d)" % [room_id, number, rule_line])
				continue
			rule_line = number
			rule = line.substr(EXITS.length()).strip_edges()
			in_legend = false
			continue
		if line.begins_with(TRAP):
			if trap_line != 0:
				errors.append("Room %s line %d: trap: is given twice (first on line %d)" % [room_id, number, trap_line])
				continue
			trap_line = number
			in_legend = false
			var value := line.substr(TRAP.length()).strip_edges()
			if value == TRAP_ALLOWED:
				trap = true
			else:
				errors.append("Room %s line %d: trap: \"%s\" is not a thing a room can say; the only value is \"%s\"" % [room_id, number, value, TRAP_ALLOWED])
			continue
		if line == LEGEND:
			in_legend = true
			continue
		if not in_legend:
			errors.append("Room %s line %d: the part above %s starts with \"%s\", not \"%s\", \"%s\" or \"%s\"" % [room_id, number, HEADER_END, line, LEGEND, EXITS + " <rule>", TRAP + " " + TRAP_ALLOWED])
			return {"legend": legend, "exits": rule, "trap": trap}
		var def := _read_legend_line(line, room_id, number, errors)
		if def == null:
			continue
		if legend.has(def.glyph):
			errors.append("Room %s line %d: legend glyph '%s' is defined twice" % [room_id, number, def.glyph])
			continue
		legend[def.glyph] = def
	return {"legend": legend, "exits": rule, "trap": trap}


static func _read_legend_line(line: String, room_id: String, number: int, errors: Array[String]) -> EntityDef:
	var where := "Room %s line %d" % [room_id, number]
	var eq := line.find("=")
	var glyph := line.substr(0, maxi(eq, 0)).strip_edges()
	if eq < 1 or glyph.length() != 1:
		errors.append("%s: a legend line looks like \"U = pickup id=name upgrade=... value=...\", not \"%s\"" % [where, line])
		return null
	if not _is_legend_glyph(glyph):
		errors.append("%s: '%s' cannot be a legend glyph; use a letter or digit that the room format does not already use (%s)" % [where, glyph, "".join(Tiles.TABLE.keys())])
		return null
	var words := line.substr(eq + 1).strip_edges().split(" ", false)
	if words.is_empty():
		errors.append("%s: legend glyph '%s' has no kind of thing after the =" % [where, glyph])
		return null
	var def := EntityDef.new()
	def.glyph = glyph
	def.type = words[0]
	for i in range(1, words.size()):
		var pair := words[i].split("=", true, 1)
		if pair.size() != 2 or pair[0].is_empty():
			errors.append("%s: \"%s\" should be key=value" % [where, words[i]])
			return null
		if pair[0] == "id":
			def.id = pair[1]
		elif def.props.has(pair[0]):
			errors.append("%s: %s= is given twice" % [where, pair[0]])
			return null
		else:
			def.props[pair[0]] = pair[1]
	for message in Entities.problems(def):
		errors.append("%s: %s" % [where, message])
	return def


static func _is_legend_glyph(glyph: String) -> bool:
	var code := glyph.unicode_at(0)
	var alphanumeric := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
	return alphanumeric and not Tiles.is_known(glyph)


static func _append_capped(errors: Array[String], found: Array[String]) -> void:
	for i in mini(found.size(), MAX_PER_KIND):
		errors.append(found[i])
	if found.size() > MAX_PER_KIND:
		errors.append("... and %d more like that in the same room" % (found.size() - MAX_PER_KIND))


static func merge_solids(rows: Array[String]) -> Array[Rect2i]:
	if rows.is_empty():
		return []
	var width := rows[0].length()
	var runs: Array[Vector3i] = []
	for y in rows.size():
		var row := rows[y]
		var x := 0
		while x < width and x < row.length():
			if Tiles.has_flag(row[x], "solid"):
				var start := x
				while x < width and x < row.length() and Tiles.has_flag(row[x], "solid"):
					x += 1
				runs.append(Vector3i(start, y, x - start))
			else:
				x += 1
	var used: Array[bool] = []
	used.resize(runs.size())
	used.fill(false)
	var rects: Array[Rect2i] = []
	for i in runs.size():
		if used[i]:
			continue
		var run := runs[i]
		var height := 1
		while true:
			var nxt := -1
			for j in runs.size():
				if used[j]:
					continue
				var other := runs[j]
				if other.y == run.y + height and other.x == run.x and other.z == run.z:
					nxt = j
					break
			if nxt == -1:
				break
			used[nxt] = true
			height += 1
		used[i] = true
		rects.append(Rect2i(run.x, run.y, run.z, height))
	return rects


static func _parse_exits(info: RoomInfo, by_pos: Dictionary, errors: Array[String]) -> Array[Door]:
	var exits: Array[Door] = []
	var rows := info.rows
	if rows.is_empty():
		return exits
	var width := rows[0].length()
	var height := rows.size()
	var cells_by_edge := {"left": [], "right": [], "up": [], "down": []}
	for y in height:
		var row := rows[y]
		for x in mini(width, row.length()):
			if not Tiles.has_flag(row[x], "door"):
				continue
			var on_x := x == 0 or x == width - 1
			var on_y := y == 0 or y == height - 1
			if on_x and on_y:
				errors.append("Room %s exit at %d,%d sits on a corner" % [info.id, x, y])
				continue
			var edge := ""
			if x == 0:
				edge = "left"
			elif x == width - 1:
				edge = "right"
			elif y == 0:
				edge = "up"
			elif y == height - 1:
				edge = "down"
			else:
				errors.append("Room %s exit at %d,%d is not on the room edge" % [info.id, x, y])
				continue
			cells_by_edge[edge].append(Vector2i(x, y))
	var screen := Grid.SCREEN_CELLS
	for edge in ["left", "right", "up", "down"]:
		var cells: Array = cells_by_edge[edge]
		if cells.is_empty():
			continue
		var side: bool = String(edge) == "left" or String(edge) == "right"
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if side:
				return a.y < b.y
			return a.x < b.x
		)
		var group_start := 0
		for i in range(1, cells.size() + 1):
			var split := i == cells.size()
			if not split:
				var prev: Vector2i = cells[i - 1]
				var cur: Vector2i = cells[i]
				if side:
					var crossed_row := int(cur.y / screen.y) != int(prev.y / screen.y)
					split = cur.y != prev.y + 1 or cur.x != prev.x or crossed_row
				else:
					var crossed_col := int(cur.x / screen.x) != int(prev.x / screen.x)
					split = cur.x != prev.x + 1 or cur.y != prev.y or crossed_col
			if split:
				var first: Vector2i = cells[group_start]
				var count := i - group_start
				var door := Door.new()
				door.edge = edge
				door.rect = Rect2i(first.x, first.y, 1, count) if side else Rect2i(first.x, first.y, count, 1)
				door.screen = _screen_cell(info, door.rect, edge)
				door.dest_id = String(by_pos.get(door.screen + Door.direction(edge), ""))
				exits.append(door)
				group_start = i
	return exits


static func _screen_cell(info: RoomInfo, rect: Rect2i, edge: String) -> Vector2i:
	var screen := Grid.SCREEN_CELLS
	match edge:
		"left":
			return info.grid_pos + Vector2i(0, int(rect.position.y / screen.y))
		"right":
			return info.grid_pos + Vector2i(info.screens.x - 1, int(rect.position.y / screen.y))
		"up":
			return info.grid_pos + Vector2i(int(rect.position.x / screen.x), 0)
		"down":
			return info.grid_pos + Vector2i(int(rect.position.x / screen.x), info.screens.y - 1)
	return info.grid_pos


static func _link_exits(order: Array[RoomInfo], rooms: Dictionary, errors: Array[String]) -> void:
	for info in order:
		for door in info.exits:
			if door.dest_id.is_empty():
				continue
			var dest: RoomInfo = rooms[door.dest_id]
			var matches: Array[Door] = []
			var span := _world_span(info, door)
			for other in dest.exits:
				if other.edge != Door.opposite(door.edge):
					continue
				if other.screen != door.screen + Door.direction(door.edge):
					continue
				if _spans_overlap(span, _world_span(dest, other)):
					matches.append(other)
			if matches.size() != 1:
				errors.append("Room %s %s exit at %s has %d matching doors in %s" % [info.id, door.edge, door.rect, matches.size(), door.dest_id])
				door.dest_id = ""
				continue
			door.dest_rect = matches[0].rect


## An opening with nothing on the other side is a wall until a room exists
## there. Closing it keeps the player from walking into the void.
static func _seal_dead_ends(info: RoomInfo) -> void:
	var open: Array[Door] = []
	for door in info.exits:
		if not door.dest_id.is_empty():
			open.append(door)
			continue
		info.sealed.append(door.rect)
		for y in range(door.rect.position.y, door.rect.end.y):
			for x in range(door.rect.position.x, door.rect.end.x):
				var row := info.rows[y]
				info.rows[y] = row.substr(0, x) + Tiles.SOLID + row.substr(x + 1)
	info.exits = open


static func _world_span(info: RoomInfo, door: Door) -> Vector2i:
	var origin := info.grid_pos * Grid.SCREEN_CELLS
	if door.is_side():
		var y0 := origin.y + door.rect.position.y
		return Vector2i(y0, y0 + door.rect.size.y)
	var x0 := origin.x + door.rect.position.x
	return Vector2i(x0, x0 + door.rect.size.x)


static func _spans_overlap(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.y and b.x < a.y
