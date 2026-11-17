extends Node

const WORLD_PATH := "res://data/world.json"
const ROOM_DIR := "res://data/rooms/"

var start_room := ""
var rooms := {}
## Title cards by room id: {"text": String, "hold": float}. A room has one if
## its entry in world.json has a `title`.
var titles := {}
## How many screens a room's camera shows across and down, by room id, for the
## rooms whose entry in world.json has a `view`. A room not in it shows one.
var views := {}
## Everything wrong with the world data. Empty means the world loaded clean.
var errors: Array[String] = []
var _by_pos := {}
var _loaded := false


func _ready() -> void:
	ensure_loaded()


func ensure_loaded() -> void:
	if _loaded:
		return
	load_from(WORLD_PATH, ROOM_DIR)


## Loads a world from `world_path` and room files in `room_dir`, replacing
## whatever was loaded. Tests use this for a small world of their own.
func load_from(world_path: String, room_dir: String) -> void:
	_loaded = true
	start_room = ""
	rooms = {}
	titles = {}
	views = {}
	errors = []
	_by_pos = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(world_path))
	if not data is Dictionary:
		errors.append("Failed to parse %s" % world_path)
		_report()
		return
	start_room = String(data.get("start_room", ""))
	var entries: Array = []
	for raw in data.get("rooms", []):
		var entry = _read_entry(raw, world_path, room_dir)
		if entry != null:
			entries.append(entry)
	var built := RoomParser.build(entries, start_room, errors)
	rooms = built["rooms"]
	_by_pos = built["by_pos"]
	_check_views()
	_report()


func get_room(id: String) -> RoomInfo:
	ensure_loaded()
	return rooms[id]


## The screens a room's camera shows, across and down: its `view`, or 1.
func view_of(id: String) -> int:
	return int(views.get(id, 1))


func id_at(grid_pos: Vector2i) -> String:
	return String(_by_pos.get(grid_pos, ""))


func _read_entry(raw, world_path := WORLD_PATH, room_dir := ROOM_DIR) -> Variant:
	if not raw is Dictionary or not raw.has("id") or not raw.get("grid_pos") is Array or raw["grid_pos"].size() != 2:
		errors.append("%s has a room entry without an id and a [x, y] grid_pos: %s" % [world_path, raw])
		return null
	var id := String(raw["id"])
	var path := room_dir + id + ".txt"
	if not FileAccess.file_exists(path):
		errors.append("Room %s has no file at %s" % [id, path])
		return null
	var pos: Array = raw["grid_pos"]
	if raw.has("title"):
		var title := read_title(raw["title"], id, errors)
		if not title.is_empty():
			titles[id] = title
	if raw.has("view"):
		var view := read_view(raw["view"], id, errors)
		if view > 1:
			views[id] = view
	return {
		"id": id,
		"grid_pos": Vector2i(int(pos[0]), int(pos[1])),
		"text": FileAccess.get_file_as_string(path),
	}


## A room's `title` from world.json as {"text", "hold"}, or empty with the
## problem added to `problems`.
static func read_title(raw, id: String, problems: Array[String]) -> Dictionary:
	if not raw is Dictionary:
		problems.append("%s: room %s has a title that is not {\"text\", \"hold\"}" % [WORLD_PATH, id])
		return {}
	if not raw.get("text") is String or String(raw["text"]).is_empty():
		problems.append("%s: room %s has a title with no text" % [WORLD_PATH, id])
		return {}
	if not (raw.get("hold") is float or raw.get("hold") is int) or float(raw["hold"]) <= 0.0:
		problems.append("%s: room %s has a title whose hold is not a number above 0" % [WORLD_PATH, id])
		return {}
	return {"text": String(raw["text"]), "hold": float(raw["hold"])}


## A room's `view` from world.json: a whole number of screens that the render
## scale allows (`RoomView.allowed`). Returns 1 with the problem added to
## `problems` when it is not.
static func read_view(raw, id: String, problems: Array[String]) -> int:
	if not (raw is int or (raw is float and raw == floorf(raw))) or not RoomView.is_allowed(int(raw)):
		problems.append("%s: room %s has a view of %s; it is one of %s (whole screens the render scale draws on whole pixels)" % [WORLD_PATH, id, raw, RoomView.allowed()])
		return 1
	return int(raw)


## A zoomed view must never show the void beyond the room.
func _check_views() -> void:
	for id: String in views.keys():
		if not rooms.has(id):
			views.erase(id)
			continue
		var info: RoomInfo = rooms[id]
		if not RoomView.fits(int(views[id]), info.screens):
			errors.append("%s: room %s has a view of %d screens but is only %d x %d screens" % [WORLD_PATH, id, int(views[id]), info.screens.x, info.screens.y])
			views.erase(id)


func _report() -> void:
	for message in errors:
		push_error(message)
