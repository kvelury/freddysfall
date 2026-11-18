extends TestCase

## Checks that are about the rooms as they are drawn, not about a mechanic.
## Update this when you change these rooms on purpose. Mechanics tests build
## their own rooms, or load tests/fixtures/worlds.


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	var four: RoomInfo = data.get_room("4")
	var nine: RoomInfo = data.get_room("9")
	check(_upgrade(four, "double_jump") and _upgrade(nine, "tongue_lash"), "room 4's machine gives double jump and room 9's gives tongue lash")
	check(data.get_room("s1").is_save_room(), "s1 is a save room")
	var pocket = preload("res://src/autoload/world_data.gd").new()
	pocket.load_from("res://tests/fixtures/worlds/pocket/world.json", "res://tests/fixtures/worlds/pocket/rooms/")
	check(pocket.errors.is_empty() and pocket.rooms.size() == 1 and pocket.start_room == "1", "a fixture world loads on its own (%s)" % [pocket.errors])
	finish("CONTENT")


func _upgrade(info: RoomInfo, upgrade: String) -> bool:
	for def in info.entities:
		if def.type == "machine" and String(def.props.get("upgrade", "")) == upgrade:
			return true
	return false
