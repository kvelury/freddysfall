extends SceneTree

## Abilities, the state that goes in a save, and the save file: written, read
## back, and survived when it is damaged, old, new, or points at a room that
## is gone. Uses its own file, never the player's save.

const TEMP := "user://save_test.json"


func _initialize() -> void:
	var ok := true
	ok = _abilities() and ok
	ok = _file() and ok
	for path in [TEMP, TEMP + ".bad"]:
		DirAccess.remove_absolute(path)
	print("SAVE %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


func _abilities() -> bool:
	var ok := true
	var width := Upgrades.get_def("imprint_width")
	var effect := Upgrades.get_def("imprint_effect")
	var a := Abilities.new()
	ok = _check(a.imprint_width == 2 and is_equal_approx(a.imprint_duration, 4.0) and a.imprint_max_active == 1 and a.imprint_effects.is_empty(), "the starting abilities are width 2, 4 s, one at a time, no effects") and ok
	ok = _check(a.apply(width, 3) and a.imprint_width == 3, "a wider upgrade widens") and ok
	ok = _check(not a.apply(width, 2) and a.imprint_width == 3, "a narrower one later takes nothing away") and ok
	ok = _check(not a.apply(width, 3), "the same one again changes nothing") and ok
	ok = _check(a.apply(Upgrades.get_def("imprint_duration"), 6.5) and is_equal_approx(a.imprint_duration, 6.5), "a longer duration lasts longer") and ok
	ok = _check(a.apply(effect, "bounce") and a.imprint_effects == ["bounce"], "an effect is gained") and ok
	ok = _check(not a.apply(effect, "bounce") and a.imprint_effects == ["bounce"], "and only once") and ok
	var b := a.copy()
	b.imprint_effects.append("glow")
	ok = _check(a.imprint_effects == ["bounce"], "a copy shares nothing with the original") and ok
	var c := Abilities.from_dict(a.to_dict())
	ok = _check(c.imprint_width == 3 and c.imprint_effects == ["bounce"] and is_equal_approx(c.imprint_duration, 6.5), "to_dict and from_dict round-trip") and ok
	var d := Abilities.from_dict({"imprint_width": 5, "unheard_of": 1})
	ok = _check(d.imprint_width == 5 and d.imprint_max_active == 1, "from_dict keeps what it knows and ignores the rest") and ok
	return ok


func _file() -> bool:
	var ok := true
	var state: Node = root.get_node("GameState")
	var save: Node = root.get_node("Save")
	save.path = TEMP
	save.enabled = true
	DirAccess.remove_absolute(TEMP)
	DirAccess.remove_absolute(TEMP + ".bad")

	state.reset()
	ok = _check(save.load_game().is_empty(), "with no save file there is nothing to load") and ok

	var def := EntityDef.new()
	def.id = "p"
	def.props = {"upgrade": "imprint_width", "value": "4"}
	state.visit("1")
	state.visit("3")
	var line: String = state.collect(def)
	ok = _check("4" in line and "Imprint width" in line, "taking a pickup says what it gave (%s)" % line) and ok
	ok = _check(state.has_flag("pickup:p") and state.abilities.imprint_width == 4, "and sets its flag and the ability") and ok
	ok = _check(save.write("3", Vector2(120.5, 80.0)), "the save is written") and ok

	state.reset()
	ok = _check(not state.has_flag("pickup:p") and state.abilities.imprint_width == 2 and state.visited.is_empty(), "resetting forgets everything") and ok
	var where: Dictionary = save.load_game()
	ok = _check(where.get("room") == "3" and where.get("position") == Vector2(120.5, 80.0), "loading says which room and where (%s)" % [where]) and ok
	ok = _check(state.has_flag("pickup:p") and state.abilities.imprint_width == 4 and state.visited.has("1") and state.visited.has("3"), "and restores the flags, abilities and visited rooms") and ok

	save.enabled = false
	ok = _check(not save.write("3", Vector2.ZERO) and save.load_game().is_empty(), "a disabled save neither writes nor reads") and ok
	save.enabled = true

	_write('{"version": 1, "room": "99", "position": [10, 10], "abilities": {"imprint_width": 5}, "flags": ["pickup:x"], "visited": ["1"]}')
	where = save.load_game()
	ok = _check(where.is_empty() and state.abilities.imprint_width == 5 and state.has_flag("pickup:x"), "a save for a room that is gone still gives the abilities, but no place") and ok

	_write("this is not json")
	ok = _check(save.load_game().is_empty() and FileAccess.file_exists(TEMP + ".bad") and not FileAccess.file_exists(TEMP), "a damaged file is set aside as .bad and the game starts fresh") and ok

	_write('{"version": 99, "room": "1", "position": [10, 10]}')
	ok = _check(save.load_game().is_empty() and not FileAccess.file_exists(TEMP), "a save from a newer game is set aside, not overwritten") and ok

	_write('{"version": 1, "room": "1"}')
	ok = _check(save.load_game().is_empty(), "a save with no position gives no place") and ok

	save.erase()
	ok = _check(not FileAccess.file_exists(TEMP), "erase removes the save") and ok
	save.enabled = false
	state.reset()
	return ok


func _write(text: String) -> void:
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
