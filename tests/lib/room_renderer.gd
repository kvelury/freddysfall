class_name RoomRenderer
extends RefCounted

## Draws rooms and the world map as images, so a drawing and its translation
## can be compared by eye. tests/render.gd (tools/render.sh) saves them through
## RenderRun. `_room_image` draws geometry always and the solver's findings only
## when given a report; a preview passes none, and adds `preview_label` to the
## header, so it cannot be mistaken for an analysed render.
##
## Colours: white solid, green door, cyan player start, purple spikes, gold a pickup, orange a door that was
## sealed because nothing is on the far side, grey dots a no-imprint cell,
## magenta a glyph the loader does not know, a checker over a door in a room
## that holds its doors shut until a rule is met, a gold box round a 3TM's 3 x 3 cells, light blue a moving platform
## where it starts and blue dots its track. Red bar on a ledge nobody can
## reach, yellow bar on a ledge you cannot get back from, grey bar on one that a
## room marked `trap: allowed` leaves one-way, red box on a door
## nobody can reach. Faint lines every 5 cells, bright lines between screens.

const PX := 8
const WORLD_PX := 4
const GUTTER := 18
const HEADER := 26
## The sentence a preview carries, and the colours of its strip.
const PREVIEW_LABEL := "PREVIEW - REACHABILITY NOT CHECKED"
const PREVIEW_BG := Color(0.95, 0.75, 0.2)
const PREVIEW_FG := Color(0.05, 0.05, 0.05)
## Rows above this y in a room image hold the id, the strip and the axis
## numbers; below it a preview is the analysed render without its overlays.
const PREVIEW_CLEAR := 14

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
const ONE_WAY := Color(0.55, 0.55, 0.55)
const TRAP := Color(0.95, 0.85, 0.1)
const LABEL := Color(0.75, 0.75, 0.75)
const PLATFORM := Color(0.55, 0.75, 1.0)
const BREAKABLE := Color(0.8, 0.45, 0.25)
const TRACK := Color(0.3, 0.45, 0.85)

## 3 x 5 digits, and the s of a save room's id, one row per string.
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
	"s": ["111", "100", "111", "001", "111"],
}


# --- one room -------------------------------------------------------------


## `report` null draws geometry only. `preview` adds the status strip to the
## header (above y = PREVIEW_CLEAR, so the drawing below it is the analysed
## render's with the overlays off).
func room_image(info: RoomInfo, report: ReachGraph.Report, preview := false) -> Image:
	var width := info.cell_size.x
	var height := info.cell_size.y
	var image := Image.create(GUTTER + width * PX, HEADER + height * PX, false, Image.FORMAT_RGB8)
	image.fill(BG)
	_text(image, info.id, 2, 2, 2, Color.WHITE)
	if preview:
		var at := 2 + info.id.length() * 8 + 8
		_strip(image, at, 3, 1)
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
				if Tiles.has_flag(row[x], "track"):
					image.fill_rect(Rect2i(cell.get_center() - Vector2i.ONE, Vector2i(2, 2)), color)
					continue
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
		elif def.type == "save":
			_box(image, _cells(SaveMachine.zone(def.cell)), THING)
	if report != null:
		for ledge in report.unreached:
			if ledge.room_id == info.id:
				_bar(image, ledge, UNREACHED)
		for ledge in report.traps:
			if ledge.room_id == info.id:
				_bar(image, ledge, TRAP)
		for ledge in report.one_way:
			if ledge.room_id == info.id:
				_bar(image, ledge, ONE_WAY)
		for pair in report.unreached_doors:
			if pair[0] == info.id:
				_box(image, _cells((pair[1] as Door).rect), UNREACHED)
	return image


## The header strip: amber with dark letters, the one thing an analysed render
## never has.
func _strip(image: Image, x: int, y: int, scale: int) -> void:
	var width := PREVIEW_LABEL.length() * 4 * scale
	image.fill_rect(Rect2i(x - 2, y - 2, width + 3, 5 * scale + 4), PREVIEW_BG)
	_text(image, PREVIEW_LABEL, x, y, scale, PREVIEW_FG, PREVIEW_FONT)


func _cell_color(glyph: String, info: RoomInfo) -> Color:
	if info.legend.has(glyph):
		var kind := (info.legend[glyph] as EntityDef).type
		return PLATFORM if kind == "platform" else (BREAKABLE if kind == "breakable" else THING)
	if Tiles.has_flag(glyph, "track"):
		return TRACK
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


func world_image(rooms: Dictionary, preview := false) -> Image:
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
					var at := origin + Vector2i(x, y) * WORLD_PX
					if Tiles.has_flag(row[x], "track"):
						image.fill_rect(Rect2i(at + Vector2i.ONE, Vector2i.ONE * 2), color)
					else:
						image.fill_rect(Rect2i(at, Vector2i(WORLD_PX, WORLD_PX)), color)
		for rect in info.sealed:
			image.fill_rect(Rect2i(origin + rect.position * WORLD_PX, rect.size * WORLD_PX), SEALED)
		_box_outline(image, Rect2i(origin, info.cell_size * WORLD_PX))
		var centre := origin + info.cell_size * WORLD_PX / 2
		var label_size := Vector2i(info.id.length() * 8 + 2, 12)
		image.fill_rect(Rect2i(centre - label_size / 2, label_size), BG)
		_text(image, info.id, centre.x - label_size.x / 2 + 1, centre.y - 5, 2, Color.WHITE)
	if not preview:
		return image
	# The strip goes on a band above the map, so no map pixel moves.
	var band := 14
	var wide := maxi(image.get_width(), PREVIEW_LABEL.length() * 8 + 6)
	var with_strip := Image.create(wide, image.get_height() + band, false, Image.FORMAT_RGB8)
	with_strip.fill(BG)
	with_strip.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, band))
	_strip(with_strip, 4, 3, 2)
	return with_strip


func _box_outline(image: Image, rect: Rect2i) -> void:
	image.fill_rect(Rect2i(rect.position.x - 1, rect.position.y - 1, rect.size.x + 2, 1), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.position.x - 1, rect.end.y, rect.size.x + 2, 1), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.position.x - 1, rect.position.y - 1, 1, rect.size.y + 2), SCREEN_LINE)
	image.fill_rect(Rect2i(rect.end.x, rect.position.y - 1, 1, rect.size.y + 2), SCREEN_LINE)


# --- digits ---------------------------------------------------------------


func _text(image: Image, text: String, x: int, y: int, scale: int, color: Color, font := DIGITS) -> void:
	var cursor := x
	for glyph in text:
		if font.has(glyph):
			var rows: Array = font[glyph]
			for row in 5:
				for col in 3:
					if String(rows[row])[col] == "1":
						image.fill_rect(Rect2i(cursor + col * scale, y + row * scale, scale, scale), color)
		cursor += 4 * scale


## 3 x 5 letters for PREVIEW_LABEL only (tool-only; DIGITS has no letters).
const PREVIEW_FONT := {
	"A": ["010", "101", "111", "101", "101"],
	"B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"],
	"D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"],
	"H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"],
	"K": ["101", "101", "110", "101", "101"],
	"L": ["100", "100", "100", "100", "111"],
	"N": ["111", "101", "101", "101", "101"],
	"O": ["010", "101", "101", "101", "010"],
	"P": ["110", "101", "110", "100", "100"],
	"R": ["110", "101", "110", "101", "101"],
	"T": ["111", "010", "010", "010", "010"],
	"V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "101", "111", "101"],
	"Y": ["101", "101", "010", "010", "010"],
	"-": ["000", "000", "111", "000", "000"],
}
