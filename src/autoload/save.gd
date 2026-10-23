extends Node

## The save file: where the player is and what they have. It is written when
## a room is entered and when a pickup is taken, and read once at boot.
## `user://` is a real folder on desktop and the browser's IndexedDB on the
## web.
##
## VERSION goes up when the file's shape changes. _migrate turns an older file
## into the current one; a file from a newer game, or one that cannot be
## read, is set aside as save.json.bad and the game starts fresh.

const VERSION := 3
## Saves older than this are from a game whose rooms and rules cannot be
## carried over. Version 1 gave Imprint away in room 2, before tokens and the
## 3TM, so its flags and rooms mean something else now.
const OLDEST := 2

var path := "user://save.json"
## Off in headless runs, so tests never touch a real save. World turns it off
## for a session started in a chosen room, which is a debugging start.
var enabled := DisplayServer.get_name() != "headless"


## Writes the game as it stands, with the player in `room_id` at `position`
## (room pixels). Returns whether it was written.
func write(room_id: String, position: Vector2) -> bool:
	if not enabled:
		return false
	var data := GameState.to_dict()
	data["version"] = VERSION
	data["room"] = room_id
	data["position"] = [position.x, position.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	return true


## Reads the save into GameState. Returns {"room": String, "position": Vector2}
## for where to put the player, or an empty dictionary if there is no save.
## A save for a room that no longer exists still restores abilities, flags and
## the map, but gives no room.
func load_game() -> Dictionary:
	if not enabled or not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var parsed := json.parse(FileAccess.get_file_as_string(path))
	var data = json.data
	if parsed != OK or not data is Dictionary or not data.get("version") is float:
		_set_aside("is not a save file")
		return {}
	if int(data["version"]) > VERSION:
		_set_aside("was written by a newer version of the game")
		return {}
	if int(data["version"]) < OLDEST:
		_set_aside("is from before tokens and the 3TM, when the world was different")
		return {}
	data = _migrate(data)
	WorldData.ensure_loaded()
	GameState.load_dict(data)
	var room := String(data.get("room", ""))
	var at = data.get("position")
	if not WorldData.rooms.has(room) or not at is Array or at.size() != 2:
		return {}
	return {"room": room, "position": Vector2(float(at[0]), float(at[1]))}


## Deletes the save. Like writing and reading, it does nothing when saving is
## off, so a test or a debugging start never touches a real file.
func erase() -> void:
	if enabled and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Turns a file of an older VERSION into the current shape. Add a step here
## each time VERSION goes up and OLDEST does not.
func _migrate(data: Dictionary) -> Dictionary:
	if int(data["version"]) < 3:
		# Version 3 made room 1 the first save room, s1, whose doors wait for
		# its machine. A game from before had left room 1 already, so the machine
		# counts as used and the player's last save is there.
		data["room"] = _renamed(String(data.get("room", "")))
		var visited := []
		for id in (data["visited"] if data.get("visited") is Array else []):
			visited.append(_renamed(String(id)))
		data["visited"] = visited
		var flags: Array = data["flags"] if data.get("flags") is Array else []
		if not flags.has("save:s1_save"):
			flags.append("save:s1_save")
		data["flags"] = flags
		data["save_room"] = "s1"
		data["version"] = 3
	return data


func _renamed(room_id: String) -> String:
	return "s1" if room_id == "1" else room_id


func _set_aside(reason: String) -> void:
	push_warning("Starting a new game, because the save at %s %s. It is kept as %s.bad." % [path, reason, path])
	DirAccess.rename_absolute(path, path + ".bad")
