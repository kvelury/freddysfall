extends SceneTree

## Loads the whole world and exits non-zero if anything about it is wrong.
## tools/validate.sh runs this.


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	for message in data.errors:
		print("FAIL ", message)
	var rooms: int = data.rooms.size()
	if data.errors.is_empty():
		print("validate pass: %d rooms, start room %s" % [rooms, data.start_room])
	else:
		print("validate fail: %d problems in %d rooms" % [data.errors.size(), rooms])
	quit(0 if data.errors.is_empty() else 1)
