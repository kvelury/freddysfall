extends SceneTree

## Draws rooms as PNGs in build/renders/, one per room plus world.png, so a
## drawing and its translation can be compared by eye. Name room ids after
## `--` to draw only those. tools/render.sh runs this.
##
## Colours: white solid, green door, cyan player start, purple spikes, gold a pickup, orange a door that was
## sealed because nothing is on the far side, grey dots a no-imprint cell,
## magenta a glyph the loader does not know, a checker over a door in a room
## that holds its doors shut until a rule is met, a gold box round a 3TM's 3 x 3 cells. Red bar on a ledge nobody can
## reach, yellow bar on a ledge you cannot get back from, red box on a door
## nobody can reach. Faint lines every 5 cells, bright lines between screens.

const PX := 8
const WORLD_PX := 4
const GUTTER := 18
const HEADER := 26
const OUT_DIR := "res://build/renders"

const BG := Color(0, 0, 0)
const GRID := Color(0.2, 0.2, 0.24)
const SCREEN_LINE := Color(0.45, 0.45, 0.7)
const SOLID := Color(1, 1, 1)
const DOOR := Color(0.2, 0.8, 0.3)
const START := Color(0.2, 0.85, 0.95)
const SEALED := Color(0.95, 0.55, 0.1)
const UNKNOWN := Color(1, 0, 1)
const HAZARD := Color(0.65, 0.35, 0.95)
const NO_IMPRINT := Color(0.5, 0.5, 0.5)
const THING := Color(0.95, 0.75, 0.2)
const UNREACHED := Color(0.95, 0.2, 0.2)
const LOCKED := Color(0.55, 0.9, 0.95)
const TRAP := Color(0.95, 0.85, 0.1)
const LABEL := Color(0.75, 0.75, 0.75)

## 3 x 5 digits, one row per string.
const DIGITS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "001", "001", "001"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
}


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	for message in data.errors:
		print("load problem: ", message)
	var report: ReachGraph.Report = null
	if data.errors.is_empty():
		var cfg := load("res://src/player/movement.tres") as MovementConfig
		report = ReachGraph.new(data.rooms, cfg).solve(data.start_room)
	var only := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ids: Array = data.rooms.keys()
	ids.sort()
	for id in ids:
		if only.is_empty() or only.has(String(id)):
			_save(_room_image(data.rooms[id], report), "room_%s.png" % id)
	if only.is_empty():
		_save(_world_image(data.rooms), "world.png")
	quit(0 if data.errors.is_empty() else 1)


func _save(image: Image, file_name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + file_name)
	var error := image.save_png(path)
	print("wrote %s (%dx%d)" % [path if error == OK else "NOTHING, error %d for %s" % [error, path], image.get_width(), image.get_height()])


# --- one room -------------------------------------------------------------


func _room_image(info: RoomInfo, report: ReachGraph.Report) -> Image:
	var width := info.cell_size.x
	var height := info.cell_size.y
	var image := Image.create(GUTTER + width * PX, HEADER + height * PX, false, Image.FORMAT_RGB8)
	image.fill(BG)
	_text(image, info.id, 2, 2, 2, Color.WHITE)
	var screen := Grid.SCREEN_CELLS
	for x in range(0, width + 1):
		if x % 5 == 0 or x % screen.x == 0:
			var color := SCREEN_LINE if x % screen.x == 0 else GRID
			image.fill_rect(Rect2i(GUTTER + x * PX, HEADER, 1, height * PX), color)
			if x < width and x % 5 == 0:
				_text(image, str(x), GUTTER + x * PX + 2, HEADER - 7, 1, LABEL)
	for y in range(0, height + 1):
		if y % 5 == 0 or y % screen.y == 0:
			var color := SCREEN_LINE if y % screen.y == 0 else GRID
			image.fill_rect(Rect2i(GUTTER, HEADER + y * PX, width * PX, 1), color)
			if y < height and y % 5 == 0:
				_text(image, str(y), 1, HEADER + y * PX + 2, 1, LABEL)
	for y in info.rows.size():
		var row := info.rows[y]
		for x in row.length():
			var color := _cell_color(row[x], info)
			if color != BG:
				var cell := Rect2i(GUTTER + x * PX, HEADER + y * PX, PX, PX)
				image.fill_rect(cell, color)
				if row[x] == Tiles.NO_IMPRINT:
					_hatch(image, cell)
	for rect in info.sealed:
		image.fill_rect(_cells(rect), SEALED)
	if info.exit_rule != ExitRules.OPEN:
		for door in info.exits:
			_checker(image, _cells(door.rect))
	for def in info.entities:
		if def.type == "machine":
			_box(image, _cells(TokenMachine.footprint(def.cell)), THING)
	if report != null:
		for ledge in report.unreached:
			if ledge.room_id == info.id:
				_bar(image, ledge, UNREACHED)
		for ledge in report.traps:
			if ledge.room_id == info.id:
				_bar(image, ledge, TRAP)
		for pair in report.unreached_doors:
			if pair[0] == info.id:
				_box(image, _cells((pair[1] as Door).rect), UNREACHED)
	return image


func _cell_color(glyph: String, info: RoomInfo) -> Color:
	if info.legend.has(glyph):
		return THING
	if not Tiles.is_known(glyph):
		return UNKNOWN
	if Tiles.has_flag(glyph, "solid"):
		return SOLID
	if Tiles.has_flag(glyph, "hazard"):
		return HAZARD
	if Tiles.has_flag(glyph, "door"):
		return DOOR
	if Tiles.has_flag(glyph, "spawn"):
		return START
	return BG


func _cells(rect: Rect2i) -> Rect2i:
	return Rect2i(GUTTER + rect.position.x * PX, HEADER + rect.position.y * PX, rect.size.x * PX, rect.size.y * PX)


func _bar(image: Image, ledge: ReachGraph.Ledge, color: Color) -> void:
	var y := HEADER + (ledge.row + 1) * PX - 3
	image.fill_rect(Rect2i(GUTTER + ledge.x0 * PX, y, (ledge.x1 - ledge.x0 + 1) * PX, 3), color)


func _box(image: Image, rect: Rect2i, color: Color) -> void:
	var outer := rect.grow(2)
	image.fill_rect(Rect2i(outer.position.x, outer.position.y, outer.size.x, 2), color)
	image.fill_rect(Rect2i(outer.position.x, outer.end.y - 2, outer.size.x, 2), color)
	image.fill_rect(Rect2i(outer.position.x, outer.position.y, 2, outer.size.y), color)
	image.fill_rect(Rect2i(outer.end.x - 2, outer.position.y, 2, outer.size.y), color)


func _checker(image: Image, area: Rect2i) -> void:
	for y in area.size.y:
		for x in area.size.x:
			if (x + y) % 2 == 0:
				image.set_pixel(area.position.x + x, area.position.y + y, LOCKED)


func _hatch(image: Image, cell: Rect2i) -> void:
	for i in range(0, PX, 2):
		image.set_pixel(cell.position.x + i, cell.position.y + i, NO_IMPRINT)


# --- the whole world ------------------------------------------------------


func _world_image(rooms: Dictionary) -> Image:
	if rooms.is_empty():
		return Image.create(1, 1, false, Image.FORMAT_RGB8)
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-(1 << 20), -(1 << 20))
	for id in rooms:
		for cell in (rooms[id] as RoomInfo).occupied_cells():
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
			high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var screen := Grid.SCREEN_CELLS
	var size := (high - low + Vector2i.ONE) * screen * WORLD_PX
	var image := Image.create(size.x + 2, size.y + 2, false, Image.FORMAT_RGB8)
	image.fill(BG)
	for id in rooms:
		var info: RoomInfo = rooms[id]
		var origin := (info.grid_pos - low) * screen * WORLD_PX + Vector2i.ONE
		for y in info.rows.size():
			var row := info.rows[y]
			for x in row.length():
				var color := _cell_color(row[x], info)
				if color != BG:
					image.fill_rect(Rect2i(origin + Vector2i(x, y) * WORLD_PX, Vector2i(WORLD_PX, WORLD_PX)), color)
		for rect in info.sealed:
			image.fill_rect(Rect2i(origin + rect.position * WORLD_PX, rect.size * WORLD_PX), SEALED)
		_box_outline(image, Rect2i(origin, info.cell_size * WORLD_PX))
		var centre := origin + info.cell_size * WORLD_PX / 2
		var label_size := Vector2i(info.id.length() * 8 + 2, 12)
		image.fill_rect(Rect2i(centre - label_size / 2, label_size), BG)
		_text(image, info.id, centre.x - label_size.x / 2 + 1, centre.y - 5, 2, Color.WHITE)
	return image


func _box_outline(image: Image, rect: Rect2i) -> void:
	image.fill_rect(Rect2i(rect.position.x - 1, rect.position.y - 1, rect.size.x + 2, 1), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.position.x - 1, rect.end.y, rect.size.x + 2, 1), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.position.x - 1, rect.position.y - 1, 1, rect.size.y + 2), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.end.x, rect.position.y - 1, 1, rect.size.y + 2), SCREEN_LINE)


# --- digits ---------------------------------------------------------------


func _text(image: Image, text: String, x: int, y: int, scale: int, color: Color) -> void:
	var cursor := x
	for glyph in text:
		if DIGITS.has(glyph):
			var rows: Array = DIGITS[glyph]
			for row in 5:
				for col in 3:
					if String(rows[row])[col] == "1":
						image.fill_rect(Rect2i(cursor + col * scale, y + row * scale, scale, scale), color)
		cursor += 4 * scale
