class_name DevLoadouts
extends RefCounted

## Named powers and resources, deliberately separate from the normal save.
## A bad/newer store remains untouched; playtesting can continue without it.

const VERSION := 1
var path := "user://dev_loadouts.json"
var entries := {}
var error := ""


func read() -> void:
	entries = {}
	error = ""
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	var parsed := json.parse(FileAccess.get_file_as_string(path))
	var data = json.data
	if parsed != OK or not data is Dictionary or data.get("version") != VERSION or not data.get("loadouts") is Dictionary:
		error = "Loadout store is damaged or from another version. It was left untouched."
		return
	for name in data["loadouts"]:
		if not name is String or name.strip_edges().is_empty() or not data["loadouts"][name] is Dictionary:
			error = "Loadout store has invalid entries. It was left untouched."
			return
	entries = data["loadouts"].duplicate(true)


## Empty means success. Changes are published in memory only after disk succeeds.
func put(name: String, loadout: Dictionary, update := false) -> String:
	name = name.strip_edges()
	if name.is_empty():
		return "Give the loadout a name."
	if entries.has(name) != update:
		return "Select an existing name to update." if update else "That name already exists."
	var problem := DevCatalog.validate(loadout)
	if not problem.is_empty():
		return problem
	var next := entries.duplicate(true)
	next[name] = loadout.duplicate(true)
	return _write(next)


func rename(old_name: String, new_name: String) -> String:
	new_name = new_name.strip_edges()
	if not entries.has(old_name) or new_name.is_empty():
		return "Select a loadout and enter a name."
	if entries.has(new_name) and old_name != new_name:
		return "That name already exists."
	var next := entries.duplicate(true)
	next[new_name] = next[old_name]
	if old_name != new_name:
		next.erase(old_name)
	return _write(next)


func remove(name: String) -> String:
	if not entries.has(name):
		return "Select a loadout."
	var next := entries.duplicate(true)
	next.erase(name)
	return _write(next)


func _write(next: Dictionary) -> String:
	if not error.is_empty():
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not write loadouts."
	file.store_string(JSON.stringify({"version": VERSION, "loadouts": next}, "  "))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or DirAccess.rename_absolute(temporary, path) != OK:
		return "Could not replace the loadout file."
	entries = next
	return ""
