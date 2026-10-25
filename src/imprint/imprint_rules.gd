class_name ImprintRules
extends RefCounted

## Where an Imprint platform may be put. A pure check over a room, so the game
## and the tests ask the same question.

## How far from a door's opening a platform has to stay, in pixels, so it
## cannot close the doorway.
const DOOR_MARGIN := float(Grid.CELL)


## Why a platform `width` cells wide, with its left end at `cell` (room cells),
## may not go there, or an empty string if it may. `player_body` is the
## player's box in room pixels. `others` are platforms that will still exist,
## in room pixels. Reasons: outside, solid, spikes, door, no_imprint, platform
## (a moving platform's track or the row above it), player, imprint.
static func check(info: RoomInfo, cell: Vector2i, width: int, player_body: Rect2, others: Array[Rect2] = []) -> String:
	# Check before constructing a rectangle: arbitrary dev values must not
	# overflow a 32-bit cell end or enter an enormous per-cell loop.
	if width < 1 or width > info.cell_size.x:
		return "outside"
	var cells := Rect2i(cell, Vector2i(width, 1))
	if not info.bounds_cells.encloses(cells):
		return "outside"
	for i in width:
		if info.is_solid(cell.x + i, cell.y):
			return "solid"
	for i in width:
		if info.is_hazard(cell.x + i, cell.y):
			return "spikes"
	var pixels := Grid.cell_rect(cells)
	for door in info.exits:
		if door.trigger_rect().grow(DOOR_MARGIN).intersects(pixels):
			return "door"
	for i in width:
		if info.is_no_imprint(cell.x + i, cell.y):
			return "no_imprint"
	for path in info.platforms:
		if pixels.intersects(path.keep_out()):
			return "platform"
	if pixels.intersects(player_body):
		return "player"
	for other in others:
		if pixels.intersects(other):
			return "imprint"
	return ""
