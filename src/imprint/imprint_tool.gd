class_name ImprintTool
extends Node2D

## Imprint: the mouse cursor is a platform. This node reads the cursor, shows
## whether a platform there is legal and reachable, places it on a click, ages
## it, and breaks it. A placed platform is a solid rect added to the player's
## collision list, so the player lands on it with no special case.
##
## It is a child of the world and uses its `current` room and `player`.

signal changed

## What a platform at the cursor would be. "unavailable", "unreachable", or
## "reachable".
const UNAVAILABLE := "unavailable"
const UNREACHABLE := "unreachable"
const REACHABLE := "reachable"

## The headless tests set `scripted` and aim with `scripted_cell`.
var scripted := false
var scripted_cell := Vector2i.ZERO

## The platforms that exist, oldest first.
var platforms: Array[ImprintPlatform] = []

var _world: Node
var _player: Player
var _state := UNAVAILABLE
var _reason := ""
var _preview_cell := Vector2i.ZERO
var _key := ""
var _mouse_seen := false
var _hidden_cursor := false


func _ready() -> void:
	# Drawn from _process, in whole pixels.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world = get_parent()
	_player = _world.get_node("Player")
	GameState.abilities_changed.connect(_forget)


## Whether the cursor is a platform right now: Imprint has been found, and the
## player is in control in a room.
func is_active() -> bool:
	return GameState.abilities.imprint_unlocked and _player.input_enabled and _world.current != null and not _world.is_busy()


func preview_state() -> String:
	return _state


## Why the cell under the cursor is unavailable, or "" if it is not.
func preview_reason() -> String:
	return _reason


## The room cell the cursor is on.
func cursor_cell() -> Vector2i:
	if scripted:
		return scripted_cell
	var room: Room = _world.current
	var local := get_global_mouse_position() - room.position
	return Vector2i(floori(local.x / float(Grid.CELL)), floori(local.y / float(Grid.CELL)))


## Puts a platform under the cursor if one may go there. Returns whether it did.
func place() -> bool:
	if not is_active():
		return false
	var room: Room = _world.current
	var cell := cursor_cell()
	var width := GameState.abilities.imprint_width
	var survivors := _survivors()
	var reason := ImprintRules.check(room.info, cell, width, _local(_player.body_rect(), room), _local_all(survivors, room))
	if not reason.is_empty():
		return false
	while platforms.size() > survivors.size():
		_break(platforms[0], true)
		platforms.remove_at(0)
	var rect := Grid.cell_rect(Rect2i(cell, Vector2i(width, 1)))
	rect.position += room.position
	platforms.append(ImprintPlatform.new(rect, GameState.abilities.imprint_duration))
	sync_solids()
	return true


## Removes every platform. With `effects` each one shatters. It leaves the
## player's collision list alone: whoever is changing rooms is about to set it.
func clear(effects: bool) -> void:
	for platform in platforms:
		if effects:
			_break(platform, false)
	platforms.clear()
	_forget()


## Works out the preview now, for the cell under the cursor.
func refresh_preview() -> void:
	_key = ""
	_update_preview()


func _physics_process(delta: float) -> void:
	if _world.current == null or _world.is_busy():
		return
	var broke := false
	for platform in platforms.duplicate():
		platform.age += delta
		if platform.expired():
			_break(platform, false)
			platforms.erase(platform)
			broke = true
	if broke:
		sync_solids()
	if is_active():
		_update_preview()


func _process(_delta: float) -> void:
	_set_cursor_hidden(is_active() and not scripted)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_seen = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("imprint"):
		place()


func _update_preview() -> void:
	var room: Room = _world.current
	var cell := cursor_cell()
	var width := GameState.abilities.imprint_width
	var player_cell := Vector2i((_player.global_position - room.position) / float(Grid.CELL))
	var key := "%s|%s|%s|%d|%d" % [cell, player_cell, _player.is_on_floor(), width, platforms.size()]
	if key == _key:
		return
	_key = key
	_preview_cell = cell
	_reason = ImprintRules.check(room.info, cell, width, _local(_player.body_rect(), room), _local_all(_survivors(), room))
	if not _reason.is_empty():
		_state = UNAVAILABLE
		return
	var rect := Grid.cell_rect(Rect2i(cell, Vector2i(width, 1)))
	rect.position += room.position
	var rects := room.world_rects()
	for platform in _survivors():
		rects.append(platform.rect)
	var reachable := ImprintReach.can_land_on(_player.config, rects, rect, _player.global_position, _player.velocity, _player.is_on_floor(), room.hazard_world_rects(), room.door_world_rects())
	_state = REACHABLE if reachable else UNREACHABLE


## The platforms that will still exist after placing another one.
func _survivors() -> Array[ImprintPlatform]:
	var keep := maxi(GameState.abilities.imprint_max_active - 1, 0)
	var out: Array[ImprintPlatform] = []
	for i in range(maxi(platforms.size() - keep, 0), platforms.size()):
		out.append(platforms[i])
	return out


func _break(platform: ImprintPlatform, _replaced: bool) -> void:
	var burst := Shatter.new()
	burst.position = platform.rect.get_center()
	add_child(burst)


## Rebuilds the player's collision list from the room and the platforms.
func sync_solids() -> void:
	var rects: Array[Rect2] = _world.current.world_rects()
	for platform in platforms:
		rects.append(platform.rect)
	_player.solids = rects
	_forget()
	changed.emit()


func _forget() -> void:
	_key = ""


func _local(rect: Rect2, room: Room) -> Rect2:
	return Rect2(rect.position - room.position, rect.size)


func _local_all(list: Array[ImprintPlatform], room: Room) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for platform in list:
		out.append(_local(platform.rect, room))
	return out


func _set_cursor_hidden(hide: bool) -> void:
	if hide == _hidden_cursor:
		return
	_hidden_cursor = hide
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE


func _draw() -> void:
	_draw_preview()
	# Last, so a platform that exists is never hidden by the one under the cursor.
	for platform in platforms:
		platform.draw(self)


func _draw_preview() -> void:
	if not is_active() or not (_mouse_seen or scripted) or _world.current == null:
		return
	var room: Room = _world.current
	var origin := room.position + Vector2(_preview_cell) * float(Grid.CELL)
	var width := GameState.abilities.imprint_width
	var area := Rect2(origin, Vector2(width * Grid.CELL, Grid.CELL))
	# Reachable or not, the cursor looks the same for now: a dotted outline
	# wherever a platform may go. The state is still worked out, for when the
	# look tells them apart again.
	if _state == UNAVAILABLE:
		_cross(origin + Vector2(Grid.CELL, Grid.CELL) * 0.5)
	else:
		_dotted(area)


## A one pixel outline, every other pixel.
func _dotted(area: Rect2) -> void:
	var x := 0
	while x < int(area.size.x):
		if x % 2 == 0:
			draw_rect(Rect2(area.position.x + x, area.position.y, 1.0, 1.0), Color.WHITE)
			draw_rect(Rect2(area.position.x + x, area.end.y - 1.0, 1.0, 1.0), Color.WHITE)
		x += 1
	var y := 0
	while y < int(area.size.y):
		if y % 2 == 0:
			draw_rect(Rect2(area.position.x, area.position.y + y, 1.0, 1.0), Color.WHITE)
			draw_rect(Rect2(area.end.x - 1.0, area.position.y + y, 1.0, 1.0), Color.WHITE)
		y += 1


func _cross(center: Vector2) -> void:
	var c := center.floor()
	# A black patch first, so the cross shows on solid floor as well as in air.
	draw_rect(Rect2(c.x - 3.0, c.y - 3.0, 7.0, 7.0), Color.BLACK)
	for i in 5:
		draw_rect(Rect2(c.x - 2.0 + i, c.y - 2.0 + i, 1.0, 1.0), Color.WHITE)
		draw_rect(Rect2(c.x - 2.0 + i, c.y + 2.0 - i, 1.0, 1.0), Color.WHITE)
