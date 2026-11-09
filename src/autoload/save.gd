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
## Room 12's top-right token became room 15's, so a save that took it has taken it.
const RETIRED_TOKEN_FLAG := "token:r12_token_spinner"
const MOVED_TOKEN_FLAG := "token:r15_token"

var path := "user://save.json"
## Off in headless runs, so tests never touch a real save. DevSession adds
## an independent isolation guard for room starts and dev playtests.
var enabled := DisplayServer.get_name() != "headless"


## Writes the game as it stands, with the player in `room_id` at `position`
## (room pixels). Returns whether it was written.
func write(room_id: String, position: Vector2) -> bool:
	if not enabled or DevSession.isolated():
		return false
	var data := GameState.to_dict()
	data["version"] = VERSION
	data["room"] = room_id
	data["position"] = [position.x, position.y]
	# Written whole to a file beside it, then put in its place, so a tab
	# closed or a crash mid-write leaves the last save as it was.
	var temporary := _temporary()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s (error %d)" % [temporary, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	var result := file.get_error()
	# On the web, closing a user:// file is what has it synced to IndexedDB.
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		push_warning("Could not replace %s (error %d)" % [path, result])
		DirAccess.remove_absolute(temporary)
		return false
	return true


## Whether there is a saved game to continue. A file that cannot be read
## still counts: load_game sets it aside and the game starts fresh. This only
## looks; load_game is what puts a finished write in place.
func has_game() -> bool:
	if not enabled or DevSession.isolated():
		return false
	return FileAccess.file_exists(path) or _whole(_temporary())


## Reads the save into GameState. Returns {"room": String, "position": Vector2}
## for where to put the player, or an empty dictionary if there is no save.
## A save for a room that no longer exists still restores abilities, flags and
## the map, but gives no room.
func load_game() -> Dictionary:
	if not enabled or DevSession.isolated():
		return {}
	_recover()
	if not FileAccess.file_exists(path):
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
	if not enabled or DevSession.isolated():
		return
	for file in [path, _temporary()]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func _temporary() -> String:
	return path + ".tmp"


## A write is finished only once its file is renamed into place. A temporary
## file with no save beside it that reads as a save was written whole and
## stopped before the rename, so it becomes the save. One that does not (a
## write cut off half way) is dropped, and so is one beside a save, which is
## a write whose rename failed: the save is kept.
func _recover() -> void:
	var temporary := _temporary()
	if not FileAccess.file_exists(temporary):
		return
	if FileAccess.file_exists(path):
		push_warning("Dropping %s, a save that was never put in place; %s is kept." % [temporary, path])
		DirAccess.remove_absolute(temporary)
	elif not _whole(temporary):
		push_warning("Dropping %s, a save cut off before it was finished." % temporary)
		DirAccess.remove_absolute(temporary)
	else:
		var result := DirAccess.rename_absolute(temporary, path)
		if result != OK:
			push_warning("Could not put %s in place of %s (error %d)." % [temporary, path, result])


## Whether `file` exists and holds a whole save: a JSON object with a version.
func _whole(file: String) -> bool:
	if not FileAccess.file_exists(file):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK:
		return false
	return json.data is Dictionary and json.data.get("version") is float


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
	# Room 12's top-right token moved to room 15 (its id was retired), so a game
	# that had taken it has taken room 15's. The tokens it carries stay as they
	# are, so room 15's exits open without a second one fitting in the pocket.
	var held: Array = data["flags"] if data.get("flags") is Array else []
	if held.has(RETIRED_TOKEN_FLAG):
		held = held.filter(func(flag) -> bool: return flag != RETIRED_TOKEN_FLAG)
		if not held.has(MOVED_TOKEN_FLAG):
			held.append(MOVED_TOKEN_FLAG)
		data["flags"] = held
	return data


func _renamed(room_id: String) -> String:
	return "s1" if room_id == "1" else room_id


func _set_aside(reason: String) -> void:
	push_warning("Starting a new game, because the save at %s %s. It is kept as %s.bad." % [path, reason, path])
	DirAccess.rename_absolute(path, path + ".bad")
