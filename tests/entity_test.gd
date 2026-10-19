extends SceneTree

## The room legend: a valid one gives things with cells and settings, and every
## way of writing one wrong is reported, in words, with its line.

const LEGEND_LINE := "  U = pickup id=a upgrade=imprint_width value=3"


func _initialize() -> void:
	var ok := true
	ok = _valid() and ok
	ok = _legend_lines() and ok
	ok = _placement() and ok
	ok = _exit_rules() and ok
	ok = _world_ids() and ok
	ok = _upgrade_file() and ok
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
	info = RoomParser.parse_room("7", Vector2i.ZERO, _room(["legend:", "", "  U   =   pickup   id=a   upgrade=imprint_effect   value=bounce", "  V = pickup id=b upgrade=imprint_duration value=6.5"], {Vector2i(5, 3): "U", Vector2i(9, 3): "V"}), errors)
	ok = _check(errors.is_empty() and info.entities.size() == 2, "extra spaces, blank lines, several things, a float and an effect all load %s" % [errors]) and ok
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
