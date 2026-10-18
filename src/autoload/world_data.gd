extends Node

const WORLD_PATH := "res://data/world.json"
const ROOM_DIR := "res://data/rooms/"

var start_room := ""
var rooms := {}
## Everything wrong with the world data. Empty means the world loaded clean.
var errors: Array[String] = []
var _by_pos := {}
var _loaded := false


func _ready() -> void:
	ensure_loaded()


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	if not data is Dictionary:
		errors.append("Failed to parse %s" % WORLD_PATH)
		_report()
		return
	start_room = String(data.get("start_room", ""))
	var entries: Array = []
	for raw in data.get("rooms", []):
		var entry = _read_entry(raw)
		if entry != null:
			entries.append(entry)
	var built := RoomParser.build(entries, start_room, errors)
	rooms = built["rooms"]
	_by_pos = built["by_pos"]
	_report()


func get_room(id: String) -> RoomInfo:
	ensure_loaded()
	return rooms[id]


func id_at(grid_pos: Vector2i) -> String:
	return String(_by_pos.get(grid_pos, ""))


func _read_entry(raw) -> Variant:
	if not raw is Dictionary or not raw.has("id") or not raw.get("grid_pos") is Array or raw["grid_pos"].size() != 2:
		errors.append("%s has a room entry without an id and a [x, y] grid_pos: %s" % [WORLD_PATH, raw])
		return null
	var id := String(raw["id"])
	var path := ROOM_DIR + id + ".txt"
	if not FileAccess.file_exists(path):
		errors.append("Room %s has no file at %s" % [id, path])
		return null
	var pos: Array = raw["grid_pos"]
	return {
		"id": id,
		"grid_pos": Vector2i(int(pos[0]), int(pos[1])),
		"text": FileAccess.get_file_as_string(path),
	}


func _report() -> void:
	for message in errors:
		push_error(message)
