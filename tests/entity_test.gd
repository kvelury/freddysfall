extends SceneTree

## The room legend: a valid one gives things with cells and settings, and every
## way of writing one wrong is reported, in words, with its line.

const LEGEND_LINE := "  U = pickup id=a upgrade=imprint_width value=3"


func _initialize() -> void:
	var ok := true
	ok = _valid() and ok
	ok = _legend_lines() and ok
	ok = _placement() and ok
	ok = _machines() and ok
	ok = _save_rooms() and ok
	ok = _exit_rules() and ok
	ok = _trap_line() and ok
	ok = _world_ids() and ok
	ok = _upgrade_file() and ok
	ok = _health() and ok
	ok = _breakable() and ok
	ok = _spike_facing() and ok
	print("ENTITY %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _valid() -> bool:
	var ok := true
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty(), "a room with a legend loads clean %s" % [errors]) and ok
	ok = _check(info.entities.size() == 1, "and has one thing") and ok
	if info.entities.size() == 1:
		var def := info.entities[0]
		ok = _check(def.type == "pickup" and def.id == "a" and def.cell == Vector2i(5, 3), "it is a pickup called a, at cell 5,3 (%s %s %s)" % [def.type, def.id, def.cell]) and ok
		ok = _check(def.props == {"upgrade": "imprint_width", "value": "3"}, "its settings are kept (%s)" % [def.props]) and ok
	ok = _check(not info.is_solid(5, 3) and not info.is_hazard(5, 3), "the glyph is open air to walk through") and ok

	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  U = pickup id=a upgrade=imprint"], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1, "an unlock pickup needs no value %s" % [errors]) and ok

	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room([], {}), errors)
	ok = _check(errors.is_empty() and info.entities.is_empty(), "a room with no header is as before") and ok

	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  T = token id=t1"], {Vector2i(5, 3): "T"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1 and info.entities[0].type == "token", "a token needs only an id %s" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  T = token id=t1 upgrade=imprint"], {Vector2i(5, 3): "T"}), errors)
	ok = _check(_has(errors, "upgrade="), "a token with a setting it does not use is an error (%s)" % [errors]) and ok

	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "", "  U   =   pickup   id=a   upgrade=imprint_effect   value=bounce", "  V = pickup id=b upgrade=imprint_duration value=6.5"], {Vector2i(5, 3): "U", Vector2i(9, 3): "V"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 2, "extra spaces, blank lines, several things, a float and an effect all load %s" % [errors]) and ok

	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  U = pickup id=a upgrade=imprint_cooldown value=0.5"], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1, "a pickup that lowers the cooldown loads (a min upgrade takes a number) %s" % [errors]) and ok
	return ok


func _legend_lines() -> bool:
	var ok := true
	var cases := [
		["an unknown kind of thing", "  U = banana id=a", "banana"],
		["no id", "  U = pickup upgrade=imprint_width value=3", "id="],
		["a missing setting", "  U = pickup id=a upgrade=imprint_width", "value="],
		["a misspelled setting", "  U = pickup id=a upgrade=imprint_width value=3 colour=red", "colour="],
		["an unknown upgrade", "  U = pickup id=a upgrade=fly value=3", "no upgrade \"fly\""],
		["a fraction where a whole number goes", "  U = pickup id=a upgrade=imprint_width value=2.5", "whole-number"],
		["words where a number goes", "  U = pickup id=a upgrade=imprint_duration value=long", "numeric"],
		["words where a cooldown goes", "  U = pickup id=a upgrade=imprint_cooldown value=long", "numeric"],
		["a value on an upgrade that takes none", "  U = pickup id=a upgrade=imprint value=3", "takes no value"],
		["a glyph the format already uses", "  X = pickup id=a upgrade=imprint_width value=3", "cannot be a legend glyph"],
		["a punctuation glyph", "  # = pickup id=a upgrade=imprint_width value=3", "cannot be a legend glyph"],
		["a two character glyph", "  UU = pickup id=a upgrade=imprint_width value=3", "legend line looks like"],
		["a setting without a value", "  U = pickup id=a upgrade", "key=value"],
		["a setting given twice", "  U = pickup id=a upgrade=imprint_width upgrade=imprint_width value=3", "given twice"],
	]
	for case in cases:
		var errors: Array[String] = []
		RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", case[1]], {Vector2i(5, 3): "U"}), errors)
		ok = _check(_has(errors, case[2]) and _has(errors, "line 2"), "%s is an error that says '%s' and the line (%s)" % [case[0], case[2], errors]) and ok

	var errors: Array[String] = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE, "  U = pickup id=b upgrade=imprint_width value=3"], {Vector2i(5, 3): "U"}), errors)
	ok = _check(_has(errors, "defined twice"), "the same glyph twice in a legend is an error (%s)" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {Vector2i(5, 3): "U"}).replace("---\n", ""), errors)
	ok = _check(_has(errors, "---"), "a legend with no --- line is an error (%s)" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["things:", LEGEND_LINE], {Vector2i(5, 3): "U"}), errors)
	ok = _check(_has(errors, "legend:"), "a header that does not start with legend: is an error (%s)" % [errors]) and ok
	return ok


func _machines() -> bool:
	var ok := true
	var legend := ["legend:", "  M = machine id=m1 upgrade=imprint"]
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "M"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1 and info.entities[0].type == "machine", "a 3TM standing on the floor loads %s" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 8): "M"}), errors)
	ok = _check(errors.is_empty(), "and one in the middle of the air %s" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(1, 16): "M"}), errors)
	ok = _check(_has(errors, "3TM m1") and _has(errors, "open air") and _has(errors, "cell 0,"), "a 3TM whose footprint reaches the wall is an error that names the cell (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "M", Vector2i(6, 15): "#"}), errors)
	ok = _check(_has(errors, "open air") and _has(errors, "cell 6,15"), "a block inside it is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "M", Vector2i(4, 14): "^"}), errors)
	ok = _check(_has(errors, "open air"), "spikes inside it are an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 1): "M"}), errors)
	ok = _check(_has(errors, "open air"), "a 3TM at the top, whose footprint leaves the room, is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  M = machine id=m1"], {Vector2i(5, 16): "M"}), errors)
	ok = _check(_has(errors, "upgrade="), "a 3TM with no upgrade is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  M = machine id=m1 upgrade=fly"], {Vector2i(5, 16): "M"}), errors)
	ok = _check(_has(errors, "no upgrade \"fly\""), "or one that gives an upgrade that does not exist (%s)" % [errors]) and ok
	return ok


func _save_rooms() -> bool:
	var ok := true
	var legend := ["legend:", "  S = save id=s2_save"]
	var errors: Array[String] = []
	var info := RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "S"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1 and info.entities[0].type == "save", "a save room with its machine on the floor loads %s" % [errors]) and ok
	ok = _check(info.is_save_room() and info.save_cell() == Vector2i(5, 16), "it is a save room and knows where its machine is (%s)" % [info.save_cell()]) and ok
	ok = _check(not RoomParser.parse_room("7", Vector2i.ZERO, _room([], {}), errors).is_save_room(), "a numbered room is not one") and ok
	errors.clear()
	info = RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 12): "S", Vector2i(3, 13): "#", Vector2i(4, 13): "#", Vector2i(5, 13): "#", Vector2i(6, 13): "#", Vector2i(7, 13): "#"}), errors)
	ok = _check(errors.is_empty(), "a machine on a platform as wide as its zone loads %s" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "S"}), errors)
	ok = _check(_has(errors, "only a room whose id is s and a number"), "a save machine in a numbered room is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room([], {}), errors)
	ok = _check(_has(errors, "needs exactly one save machine") and _has(errors, "has 0"), "a save room with no machine is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(["legend:", "  S = save id=s2_save", "  T = save id=s2_other"], {Vector2i(5, 16): "S", Vector2i(15, 16): "T"}), errors)
	ok = _check(_has(errors, "needs exactly one save machine") and _has(errors, "has 2"), "and one with two is too (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 12): "S"}), errors)
	ok = _check(_has(errors, "save machine s2_save") and _has(errors, "solid floor"), "a machine over air, where nobody could stand to come back, is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 12): "S", Vector2i(3, 13): "#", Vector2i(4, 13): "#", Vector2i(5, 13): "#", Vector2i(6, 13): "#"}), errors)
	ok = _check(_has(errors, "solid floor") and _has(errors, "(7,13)"), "a platform one cell short of its zone, where the player could be popped onto air, is an error naming the cell (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "S", Vector2i(7, 15): "#"}), errors)
	ok = _check(_has(errors, "save machine s2_save") and _has(errors, "open air") and _has(errors, "cell 7,15"), "a wall in the zone, beside the 3 x 3 the machine fills, is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(["legend:", "  S = save id=s2_save", "  T = token id=s2_token"], {Vector2i(5, 16): "S", Vector2i(20, 16): "T"}), errors)
	ok = _check(_has(errors, "holds nothing but its save machine") and _has(errors, "1 other thing"), "a save room with a token in it is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(5, 16): "S", Vector2i(20, 16): "^"}), errors)
	ok = _check(_has(errors, "holds nothing but its save machine") and _has(errors, "spikes"), "and so is one with spikes (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(legend, {Vector2i(1, 16): "S"}), errors)
	ok = _check(_has(errors, "save machine s2_save") and _has(errors, "open air"), "one whose footprint reaches the wall is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(["legend:", "  S = save id=s2_save upgrade=imprint"], {Vector2i(5, 16): "S"}), errors)
	ok = _check(_has(errors, "upgrade="), "a save machine takes no settings (%s)" % [errors]) and ok

	errors.clear()
	info = RoomParser.parse_room("s2", Vector2i.ZERO, _room(["exits: saved"] + legend, {Vector2i(5, 16): "S"}), errors)
	ok = _check(errors.is_empty() and info.exit_rule == "saved", "exits: saved loads in a room with a save machine %s" % [errors]) and ok
	ok = _check(not ExitRules.met(info, {}) and not ExitRules.met(info, {"save:other": true}) and ExitRules.met(info, {"save:s2_save": true}), "and the doors wait for that machine's flag") and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: saved"], {}), errors)
	ok = _check(_has(errors, "no save machine"), "exits: saved with no machine is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("s2", Vector2i.ZERO, _room(["exits: pickups"] + legend, {Vector2i(5, 16): "S"}), errors)
	ok = _check(_has(errors, "no pickup or token"), "a save machine is not something to take for exits: pickups (%s)" % [errors]) and ok

	for id in ["4", "12", "s1", "s12"]:
		ok = _check(RoomParser.is_valid_id(id), "room id %s is allowed" % id) and ok
	for id in ["", "s", "a3", "-1", "s-1", "1a", "+2", "ss1", "1s"]:
		ok = _check(not RoomParser.is_valid_id(id), "room id \"%s\" is not" % id) and ok
	errors.clear()
	RoomParser.build([{"id": "a3", "grid_pos": Vector2i.ZERO, "text": _room([], {Vector2i(2, 16): "P"})}], "a3", errors)
	ok = _check(_has(errors, "\"a3\" is not allowed"), "a world with a room called a3 is an error (%s)" % [errors]) and ok
	return ok


func _exit_rules() -> bool:
	var ok := true
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: pickups", "legend:", LEGEND_LINE], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty() and info.exit_rule == "pickups", "exits: pickups loads, before the legend %s" % [errors]) and ok
	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE, "exits: pickups"], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty() and info.exit_rule == "pickups", "and after it %s" % [errors]) and ok
	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: open"], {}), errors)
	ok = _check(errors.is_empty() and info.exit_rule == "open", "a header can hold only exits: %s" % [errors]) and ok
	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room([], {}), errors)
	ok = _check(info.exit_rule == "open", "a room with no rule is open") and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: banana"], {}), errors)
	ok = _check(_has(errors, "banana") and _has(errors, "rules:"), "an unknown rule is an error that lists the rules (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: pickups"], {}), errors)
	ok = _check(_has(errors, "no pickup or token"), "pickups in a room with nothing to take is an error (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: open", "exits: pickups"], {}), errors)
	ok = _check(_has(errors, "given twice") and _has(errors, "line 2"), "a rule given twice is an error with its line (%s)" % [errors]) and ok
	return ok


func _trap_line() -> bool:
	var ok := true
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(["trap: allowed"], {}), errors)
	ok = _check(errors.is_empty() and info.traps_allowed, "trap: allowed loads %s" % [errors]) and ok
	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["trap: allowed", "exits: pickups", "legend:", LEGEND_LINE], {Vector2i(5, 3): "U"}), errors)
	ok = _check(errors.is_empty() and info.traps_allowed and info.exit_rule == "pickups" and info.entities.size() == 1, "and sits beside exits: and a legend %s" % [errors]) and ok
	errors.clear()
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room([], {}), errors)
	ok = _check(not info.traps_allowed, "a room with no trap line allows no trap") and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["trap: sometimes"], {}), errors)
	ok = _check(_has(errors, "sometimes") and _has(errors, "allowed") and _has(errors, "line 1"), "any other value is an error that says what is allowed (%s)" % [errors]) and ok
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["trap: allowed", "trap: allowed"], {}), errors)
	ok = _check(_has(errors, "given twice") and _has(errors, "line 2"), "a trap line given twice is an error with its line (%s)" % [errors]) and ok
	return ok


func _placement() -> bool:
	var ok := true
	var errors: Array[String] = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {}), errors)
	ok = _check(_has(errors, "never drawn"), "a legend glyph that is not on the grid is an error (%s)" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {Vector2i(5, 3): "U", Vector2i(8, 3): "U"}), errors)
	ok = _check(_has(errors, "drawn 2 times"), "one glyph drawn twice is an error (%s)" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {Vector2i(0, 3): "U"}), errors)
	ok = _check(_has(errors, "outer wall"), "a legend glyph in the outer wall is an error (%s)" % [errors]) and ok

	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", LEGEND_LINE], {Vector2i(5, 3): "U", Vector2i(8, 3): "V"}), errors)
	ok = _check(_has(errors, "'V'") and _has(errors, "not a known glyph"), "a glyph with no legend line is still an unknown glyph (%s)" % [errors]) and ok
	return ok


func _world_ids() -> bool:
	var errors: Array[String] = []
	var entries := []
	for id in ["1", "2"]:
		var text := _room(["legend:", LEGEND_LINE], {Vector2i(5, 3): "U", Vector2i(2, 16): "P"})
		entries.append({"id": id, "grid_pos": Vector2i(int(id) - 1, 0), "text": text})
	RoomParser.build(entries, "1", errors)
	return _check(_has(errors, "id \"a\" is used in room 1 and room 2"), "the same id in two rooms is an error (%s)" % [errors])


func _upgrade_file() -> bool:
	var ok := _check(Upgrades.problems().is_empty(), "data/upgrades.json is valid %s" % [Upgrades.problems()])
	for id in Upgrades.all():
		var def: Dictionary = Upgrades.all()[id]
		ok = _check(Abilities.STATS.has(def["stat"]) and Abilities.new().get(def["stat"]) != null, "upgrade %s changes a real ability (%s)" % [id, def["stat"]]) and ok
	return ok


## A one-screen room: walls all round, `header` lines and a --- line above it
## when there is a header, and `marks` (cell -> glyph) drawn in.
## A health pip: a thing with only an id, taken by touch, that an `exits:
## pickups` room waits for, and that adds one to the player's health.
func _health() -> bool:
	var ok := true
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: pickups", "legend:", "  H = health id=h1"], {Vector2i(5, 3): "H"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1 and info.entities[0].type == "health", "a health pip needs only an id %s" % [errors]) and ok
	var def := info.entities[0]
	ok = _check(Entities.is_collectible(def) and Entities.flag_for(def) == "health:h1", "it is taken by touch, with the flag health:h1") and ok
	ok = _check(not ExitRules.met(info, {}) and ExitRules.met(info, {"health:h1": true}), "exits: pickups waits for it") and ok
	ok = _check(Entities.present(def, {}) and not Entities.present(def, {"health:h1": true}), "and once taken the room builds without it") and ok
	var node := Entities.create(def)
	ok = _check(node is HealthPip, "it builds as a HealthPip") and ok
	node.free()
	var room := Room.new()
	room.build(info)
	var touched := room.touched_things(Rect2(Grid.cell_center(Vector2i(5, 3)) - Vector2(5, 5), Vector2(10, 10)))
	ok = _check(touched.size() == 1 and touched[0] is HealthPip, "a body over it in a built room touches it, so it is taken") and ok
	room.free()
	errors.clear()
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  H = health id=h1 value=2"], {Vector2i(5, 3): "H"}), errors)
	ok = _check(_has(errors, "value="), "a setting it does not use is an error (%s)" % [errors]) and ok
	var state: Node = root.get_node("GameState")
	state.reset()
	state.take_health(def)
	ok = _check(state.health == 1 and state.has_flag("health:h1"), "taking it adds one pip, and the HUD shows it with no line") and ok
	state.take_health(def)
	ok = _check(state.health == 2 and state.max_health == 2, "pips add up, and so does the bar") and ok
	state.reset()
	return ok


## Spikes point away from the solid they sit against, a floor first.
func _spike_facing() -> bool:
	var ok := true
	var errors: Array[String] = []
	var marks := {Vector2i(5, 16): "^", Vector2i(30, 5): "^", Vector2i(1, 5): "^", Vector2i(10, 1): "^", Vector2i(15, 8): "^", Vector2i(30, 16): "^"}
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room([], marks), errors)
	ok = _check(errors.is_empty(), "a room of spikes loads %s" % [errors]) and ok
	ok = _check(info.spike_facing(Vector2i(5, 16)) == Vector2i.UP, "spikes on a floor point up") and ok
	ok = _check(info.spike_facing(Vector2i(30, 5)) == Vector2i.LEFT, "on a right wall, left") and ok
	ok = _check(info.spike_facing(Vector2i(1, 5)) == Vector2i.RIGHT, "on a left wall, right") and ok
	ok = _check(info.spike_facing(Vector2i(10, 1)) == Vector2i.DOWN, "under a ceiling, down") and ok
	ok = _check(info.spike_facing(Vector2i(15, 8)) == Vector2i.UP, "in open air, up") and ok
	ok = _check(info.spike_facing(Vector2i(30, 16)) == Vector2i.UP, "in a corner, the floor wins") and ok
	return ok


func _room(header: Array, marks: Dictionary) -> String:
	var rows: Array[String] = []
	for y in 18:
		var row := ""
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 17
			row += marks.get(Vector2i(x, y), "#" if edge else ".")
		rows.append(row)
	var text := "\n".join(rows) + "\n"
	if header.is_empty():
		return text
	return "\n".join(header) + "\n---\n" + text


func _has(lines: Array[String], needle: String) -> bool:
	for line in lines:
		if needle in line:
			return true
	return false


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond


## A breakable wall: one glyph drawn on every cell of one connected shape, solid
## while it stands, not collectible, and refused where it would be broken.
func _breakable() -> bool:
	var ok := true
	var legend := ["legend:", "  B = breakable id=w1"]
	var wall := {}
	for y in range(5, 9):
		wall[Vector2i(10, y)] = "B"
	var errors: Array[String] = []
	var info := RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, wall), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 1 and info.entities[0].type == "breakable" and info.entities[0].cells.size() == 4, "a wall drawn on four cells loads as one thing %s" % [errors]) and ok
	ok = _check(info.is_solid(10, 6) and info.solids.all(func(r: Rect2i) -> bool: return not r.has_point(Vector2i(10, 6))), "it is solid, but not one of the room's plain solids") and ok
	ok = _check(info.standing_wall_at(Vector2i(10, 6)) == "w1" and info.variant(["w1"] as Array[String]).standing_wall_at(Vector2i(10, 6)) == "" and not info.variant(["w1"] as Array[String]).is_solid(10, 6), "and a variant with it broken has it open") and ok
	ok = _check(not Entities.is_collectible(info.entities[0]) and not Entities.is_touchable(info.entities[0]), "it is not something to take or touch") and ok

	var pieces := {Vector2i(10, 5): "B", Vector2i(10, 6): "B", Vector2i(10, 9): "B"}
	errors = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, pieces), errors)
	ok = _check(_has(errors, "do not touch"), "a wall in two pieces is an error %s" % [errors]) and ok

	errors = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(legend, {Vector2i(0, 5): "B"}), errors)
	ok = _check(_has(errors, "outer wall"), "a wall cell in the outer wall is an error %s" % [errors]) and ok

	errors = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  B = breakable"], {Vector2i(10, 5): "B"}), errors)
	ok = _check(_has(errors, "needs an id"), "a wall needs an id %s" % [errors]) and ok

	errors = []
	RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "  B = breakable id=w1 hits=5"], {Vector2i(10, 5): "B"}), errors)
	ok = _check(_has(errors, "does not use"), "and takes no other setting yet %s" % [errors]) and ok

	errors = []
	RoomParser.parse_room("s1", Vector2i.ZERO, _room(["legend:", "  B = breakable id=w1", "  S = save id=s1_save"], {Vector2i(10, 5): "B", Vector2i(16, 15): "S"}), errors)
	ok = _check(_has(errors, "holds nothing but"), "a save room cannot hold one %s" % [errors]) and ok

	errors = []
	var pickups := RoomParser.parse_room("7", Vector2i.ZERO, _room(["exits: pickups", "legend:", "  B = breakable id=w1"], {Vector2i(10, 5): "B"}), errors)
	ok = _check(pickups != null and not errors.is_empty(), "`exits: pickups` does not count a wall as something to take, so a room with only a wall refuses it %s" % [errors]) and ok

	var node := Entities.create(info.entities[0])
	ok = _check(node is BreakableWall, "it builds as a BreakableWall") and ok
	node.free()
	return ok
