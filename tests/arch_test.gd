extends TestCase

## The rules the code keeps, checked as text so a shortcut cannot land quietly:
## progression is changed through GameState's methods, and the pure code
## (the parser, the dev catalog, src/core) does not name an autoload.


func _initialize() -> void:
	_writes()
	_pure()
	_snapshot()
	finish("ARCH")


func _writes() -> void:
	var pattern := RegEx.create_from_string("GameState\\.(flags|machines|visited)\\s*\\[[^\\]]*\\]\\s*=|GameState\\.(save_room|map_zoom|tokens|health|max_health|abilities)\\s*=[^=]")
	for path in _scripts("res://src"):
		if path.ends_with("/game_state.gd"):
			continue
		var found := pattern.search(FileAccess.get_file_as_string(path))
		check(found == null, "nothing but GameState assigns its fields (%s)" % path)


func _pure() -> void:
	var named := RegEx.create_from_string("\\b(GameState|DevSession|WorldData|Save)\\b")
	for path in _scripts("res://src/core"):
		var found := named.search(FileAccess.get_file_as_string(path))
		check(found == null, "src/core does not name an autoload (%s)" % path)
	for path in ["res://src/world/room_parser.gd", "res://src/dev/dev_catalog.gd"]:
		var found := named.search(FileAccess.get_file_as_string(path))
		check(found == null, "%s does not name an autoload" % path)


func _snapshot() -> void:
	var written := Progression.new().to_dict()
	for property in Progression.new().get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var name := String(property["name"])
			check(written.has(name), "a save writes the %s field" % name)


func _scripts(root_path: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root_path, out)
	return out


func _walk(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var full := path.path_join(name)
			if dir.current_is_dir():
				_walk(full, out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = dir.get_next()
