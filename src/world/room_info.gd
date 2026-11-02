class_name RoomInfo
extends RefCounted

var id := ""
var grid_pos := Vector2i.ZERO
var screens := Vector2i.ONE
var cell_size := Vector2i(32, 18)
var pixel_size := Vector2(320, 180)
## Local cells an imprint platform must lie fully inside.
var bounds_cells := Rect2i(0, 0, 32, 18)
var has_spawn := false
var spawn_cell := Vector2i(2, 16)
## The room as loaded. Openings that lead nowhere have been sealed to solid.
var rows: Array[String] = []
var solids: Array[Rect2i] = []
var exits: Array[Door] = []
## Openings the loader closed because nothing was on the other side.
var sealed: Array[Rect2i] = []
var no_imprint: Array[Vector2i] = []
## Cells that kill on touch.
var hazards: Array[Vector2i] = []
## The room's legend: glyph -> EntityDef. Only things drawn in the room are in
## `entities`, in legend order, with their cells.
var legend := {}
var entities: Array[EntityDef] = []
## The room's moving platforms, in legend order. Each is also in `entities`.
var platforms: Array[PlatformPath] = []
## Every moving thing in the room, in legend order: the platforms above, then any
## emitters and spinners. This is what a body's `Movers` is built from.
var movers: Array[Mover] = []
## The emitters among them.
var emitters: Array[EmitterPath] = []
## And the spinners.
var spinners: Array[SpinnerPath] = []
## What has to be true before the room's doors work, a key of ExitRules.RULES.
var exit_rule := "open"
## Whether the room is meant to be a dead end the player cannot climb out of yet
## (`trap: allowed`). A way home that is missing is a warning here, not an error.
var traps_allowed := false
## Breakable walls: id -> the cells each is drawn on. They are solid while they
## stand, and are not in `solids`; see `all_solids`.
var breakables := {}
## The ids of the walls that are broken. A room as loaded has none, and a
## Room (or the solver) works on a `variant` that has its own.
var broken: Array[String] = []
var _wall_at := {}
## For the solver's copies of a room (see `solver_variant`): the id of the room
## they are a copy of. Empty on a room as loaded.
var base_id := ""


## Whether this is a save room: its id is `s` and a number (`s1`). Dying on the
## last heart sends the player back to the save room they last entered.
func is_save_room() -> bool:
	return is_save_id(id)


static func is_save_id(room_id: String) -> bool:
	return room_id.begins_with("s")


## The cell of the room's save machine, or (-1, -1) if it has none.
func save_cell() -> Vector2i:
	for def in entities:
		if def.type == "save":
			return def.cell
	return Vector2i(-1, -1)


func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for sy in screens.y:
		for sx in screens.x:
			cells.append(grid_pos + Vector2i(sx, sy))
	return cells


func is_solid(x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return true
	var row := rows[y]
	if x < 0 or x >= row.length():
		return true
	if not _wall_at.is_empty() and standing_wall_at(Vector2i(x, y)) != "":
		return true
	return Tiles.has_flag(row[x], "solid")


## Records a breakable wall's cells (the parser does this).
func register_breakable(wall_id: String, cells: Array[Vector2i]) -> void:
	breakables[wall_id] = cells
	for cell in cells:
		_wall_at[cell] = wall_id


## The id of the breakable wall that stands on `cell`, or "" if none does (no
## wall there, or it is broken).
func standing_wall_at(cell: Vector2i) -> String:
	var wall_id: String = _wall_at.get(cell, "")
	if wall_id.is_empty() or broken.has(wall_id):
		return ""
	return wall_id


## The room's solids and the cells of the walls that still stand, as cell rects,
## for whatever has to collide with the room as it is now.
func all_solids() -> Array[Rect2i]:
	var out := solids.duplicate()
	for wall_id in breakables:
		if broken.has(wall_id):
			continue
		for cell: Vector2i in breakables[wall_id]:
			out.append(Rect2i(cell, Vector2i.ONE))
	return out


## This room with the walls in `broken_ids` broken. Everything else is shared
## with this one, so it is cheap; only `broken` is its own.
func variant(broken_ids: Array[String]) -> RoomInfo:
	var out := RoomInfo.new()
	out.id = id
	out.grid_pos = grid_pos
	out.screens = screens
	out.cell_size = cell_size
	out.pixel_size = pixel_size
	out.bounds_cells = bounds_cells
	out.has_spawn = has_spawn
	out.spawn_cell = spawn_cell
	out.rows = rows
	out.solids = solids
	out.exits = exits
	out.sealed = sealed
	out.no_imprint = no_imprint
	out.hazards = hazards
	out.legend = legend
	out.entities = entities
	out.platforms = platforms
	out.movers = movers
	out.emitters = emitters
	out.spinners = spinners
	out.exit_rule = exit_rule
	out.traps_allowed = traps_allowed
	out.breakables = breakables
	out._wall_at = _wall_at
	out.broken = broken_ids.duplicate()
	out.base_id = base_id
	return out


## The id of the room as loaded: `id` itself, or for a solver variant the room it
## copies.
func base() -> String:
	return base_id if not base_id.is_empty() else id


## What names a room with some walls broken in the solver: the id, then `~` and
## the broken ids in order. The room as loaded is just its id.
static func key_for(room_id: String, broken_ids: Array[String]) -> String:
	if broken_ids.is_empty():
		return room_id
	var sorted := broken_ids.duplicate()
	sorted.sort()
	return "%s~%s" % [room_id, "~".join(sorted)]


## `variant` for the solver, which keys everything by `id`: the copy has the
## key as its id, so what the solver keeps for it (ledges, edges, cache files)
## stays apart from the room as loaded. Doors still lead to `base()`'s neighbours
## by their own `dest_id`.
func solver_variant(broken_ids: Array[String]) -> RoomInfo:
	var out := variant(broken_ids)
	out.base_id = base()
	out.id = key_for(base(), broken_ids)
	return out


## Room-local pixels where the player is put when a room is started in
## directly, not entered through a door: on its P, or else just inside its
## first door, to fall from there.
func start_position() -> Vector2:
	if has_spawn or exits.is_empty():
		return Grid.cell_center(spawn_cell)
	return exits[0].doorway(self)


func exit_on(edge: String) -> Door:
	for door in exits:
		if door.edge == edge:
			return door
	return null


func door_by_rect(rect: Rect2i) -> Door:
	for door in exits:
		if door.rect == rect:
			return door
	return null


func is_no_imprint(x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return false
	var row := rows[y]
	if x < 0 or x >= row.length():
		return false
	return Tiles.has_flag(row[x], "no_imprint")


## Which way the teeth of the spikes at `cell` point: away from the solid
## they sit against. A floor under them wins, then a wall to the right, a wall
## to the left, and a ceiling; spikes in open air point up. Only the drawing
## turns; the whole cell is still deadly.
func spike_facing(cell: Vector2i) -> Vector2i:
	if is_solid(cell.x, cell.y + 1):
		return Vector2i.UP
	if is_solid(cell.x + 1, cell.y):
		return Vector2i.LEFT
	if is_solid(cell.x - 1, cell.y):
		return Vector2i.RIGHT
	if is_solid(cell.x, cell.y - 1):
		return Vector2i.DOWN
	return Vector2i.UP


func is_hazard(x: int, y: int) -> bool:
	if y < 0 or y >= rows.size():
		return false
	var row := rows[y]
	if x < 0 or x >= row.length():
		return false
	return Tiles.has_flag(row[x], "hazard")
