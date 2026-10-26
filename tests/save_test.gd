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
	var unlock := Upgrades.get_def("imprint")
	ok = _check(not a.imprint_unlocked, "Imprint starts locked") and ok
	ok = _check(a.apply(unlock, true) and a.imprint_unlocked, "the Imprint upgrade unlocks it") and ok
	ok = _check(not a.apply(unlock, true) and a.imprint_unlocked, "and does nothing the second time") and ok
	ok = _check(Abilities.from_dict(a.to_dict()).imprint_unlocked, "the unlock survives to_dict and from_dict") and ok
	a = Abilities.new()
	ok = _check(a.imprint_width == 2 and is_equal_approx(a.imprint_duration, 1.5) and a.imprint_max_active == 1 and is_zero_approx(a.imprint_cooldown) and a.imprint_effects.is_empty(), "the starting abilities are width 2, 1.5 s, one at a time, no cooldown, no effects") and ok
	ok = _check(a.apply(width, 4) and a.imprint_width == 4, "a wider upgrade widens") and ok
	ok = _check(not a.apply(width, 3) and a.imprint_width == 4, "a narrower one later takes nothing away") and ok
	ok = _check(not a.apply(width, 4), "the same one again changes nothing") and ok
	ok = _check(Abilities.from_dict({"imprint_width": 2}).imprint_width == 2, "an old save keeps the width it stored") and ok
	ok = _check(a.apply(Upgrades.get_def("imprint_duration"), 6.5) and is_equal_approx(a.imprint_duration, 6.5), "a longer duration lasts longer") and ok
	ok = _check(a.apply(effect, "bounce") and a.imprint_effects == ["bounce"], "an effect is gained") and ok
	ok = _check(not a.apply(effect, "bounce") and a.imprint_effects == ["bounce"], "and only once") and ok
	var b := a.copy()
	b.imprint_effects.append("glow")
	ok = _check(a.imprint_effects == ["bounce"], "a copy shares nothing with the original") and ok
	var c := Abilities.from_dict(a.to_dict())
	ok = _check(c.imprint_width == 4 and c.imprint_effects == ["bounce"] and is_equal_approx(c.imprint_duration, 6.5), "to_dict and from_dict round-trip") and ok
	var d := Abilities.from_dict({"imprint_width": 5, "unheard_of": 1})
	ok = _check(d.imprint_width == 5 and d.imprint_max_active == 1, "from_dict keeps what it knows and ignores the rest") and ok

	# The cooldown is a "min" upgrade: lower is better, and nothing is taken away.
	var cooldown := Upgrades.get_def("imprint_cooldown")
	var e := Abilities.new()
	e.imprint_cooldown = 0.5
	ok = _check(e.apply(cooldown, 0.2) and is_equal_approx(e.imprint_cooldown, 0.2), "a shorter cooldown is taken") and ok
	ok = _check(not e.apply(cooldown, 0.4) and is_equal_approx(e.imprint_cooldown, 0.2), "a longer one later takes nothing away") and ok
	ok = _check(not e.apply(cooldown, 0.2) and is_equal_approx(e.imprint_cooldown, 0.2), "the same one again changes nothing") and ok
	ok = _check(is_equal_approx(Abilities.from_dict(e.to_dict()).imprint_cooldown, 0.2), "the cooldown survives to_dict and from_dict") and ok
	ok = _check(is_zero_approx(Abilities.from_dict({"imprint_width": 3}).imprint_cooldown), "a save without a cooldown loads with it off") and ok
	ok = _check(is_equal_approx(Abilities.from_dict({"imprint_duration": 2.5}).imprint_duration, 2.5), "and an old save keeps the duration it stored") and ok
	ok = _check(Upgrades.check("imprint_cooldown", "0.5").is_empty() and not Upgrades.check("imprint_cooldown", "long").is_empty(), "a cooldown pickup takes a number") and ok
	ok = _check(Abilities.new().describe() == "imprint locked" and e.describe() == "imprint locked", "describe is unchanged while Imprint is locked") and ok
	e.imprint_unlocked = true
	var plain := Abilities.new()
	plain.imprint_unlocked = true
	ok = _check(e.describe().contains("0.2 s cooldown") and not plain.describe().contains("cooldown"), "describe names a cooldown only when there is one") and ok
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

	# Tokens and how full each 3TM is come back too.
	var token := EntityDef.new()
	token.type = "token"
	token.id = "t"
	state.reset()
	state.take_token(token)
	state.take_token(token)
	state.machines["m"] = 2
	save.write("3", Vector2(10, 10))
	state.reset()
	ok = _check(state.tokens == 0 and state.machines.is_empty(), "resetting empties the pockets and the machines") and ok
	save.load_game()
	ok = _check(state.tokens == 2 and state.machines == {"m": 2} and state.has_flag("token:t"), "a save keeps the tokens carried, the machines' fill and the token flag (%d, %s)" % [state.tokens, state.machines]) and ok
	state.reset()
	for i in 5:
		state.take_token(token)
	ok = _check(state.tokens == _cap(state), "a pocket holds at most the cap (%d)" % state.tokens) and ok
	_write('{"version": 2, "room": "1", "position": [10, 10], "tokens": 99, "machines": {"m": 7, "n": "x"}}')
	save.load_game()
	ok = _check(state.tokens == _cap(state) and state.machines.get("m") == 3, "a damaged save cannot hold more than the cap or fill a machine past three (%d, %s)" % [state.tokens, state.machines]) and ok

	# The map's zoom is saved with the game.
	state.reset()
	state.map_zoom = 2
	save.write("3", Vector2(10, 10))
	state.reset()
	save.load_game()
	ok = _check(state.map_zoom == 2, "a save keeps the map's zoom (%d)" % state.map_zoom) and ok

	# The save room and the health come back, and a damaged value cannot hurt.
	state.reset()
	ok = _check(state.save_room == "" and state.health == 0, "a new game has no save room and no health") and ok
	state.save_room = "s1"
	state.health = 3
	save.write("s1", Vector2(165, 85))
	state.reset()
	ok = _check(state.save_room == "" and state.health == 0, "resetting forgets them") and ok
	where = save.load_game()
	ok = _check(state.save_room == "s1" and state.health == 3 and where.get("room") == "s1", "a save keeps the save room and the health (%s, %d)" % [state.save_room, state.health]) and ok
	_write('{"version": 3, "room": "s1", "position": [10, 10], "save_room": 5, "health": -4}')
	save.load_game()
	ok = _check(state.save_room == "" and state.health == 0, "a save room that is not text, or health below zero, is dropped (%s, %d)" % [state.save_room, state.health]) and ok

	# A game from before room 1 became the save room s1 carries over.
	_write('{"version": 2, "room": "1", "position": [10, 10], "visited": ["1", "2"], "flags": ["token:r2_token"]}')
	where = save.load_game()
	ok = _check(where.get("room") == "s1" and state.visited.has("s1") and state.visited.has("2") and not state.visited.has("1"), "a version 2 save has room 1 renamed s1 (%s, %s)" % [where, state.visited.keys()]) and ok
	ok = _check(state.has_flag("save:s1_save") and state.has_flag("token:r2_token") and state.save_room == "s1", "its machine counts as used and it keeps what it had") and ok
	_write('{"version": 2, "room": "1", "position": [10, 10], "visited": "x", "flags": 5}')
	where = save.load_game()
	ok = _check(where.get("room") == "s1" and state.has_flag("save:s1_save"), "and a version 2 save with damaged lists still loads") and ok

	save.enabled = false
	ok = _check(not save.write("3", Vector2.ZERO) and save.load_game().is_empty(), "a disabled save neither writes nor reads") and ok
	save.enabled = true

	_write('{"version": 1, "room": "1", "position": [10, 10], "flags": ["pickup:r2_imprint"]}')
	ok = _check(save.load_game().is_empty() and FileAccess.file_exists(TEMP + ".bad") and not FileAccess.file_exists(TEMP), "a save from the world where Imprint was free is set aside, not loaded") and ok
	DirAccess.remove_absolute(TEMP + ".bad")

	_write('{"version": 2, "room": "99", "position": [10, 10], "abilities": {"imprint_width": 5}, "flags": ["pickup:x"], "visited": ["1"]}')
	where = save.load_game()
	ok = _check(where.is_empty() and state.abilities.imprint_width == 5 and state.has_flag("pickup:x"), "a save for a room that is gone still gives the abilities, but no place") and ok

	_write('{"version": 3, "room": "s2", "position": [165, 165], "save_room": "s2", "health": 2, "abilities": {"imprint_unlocked": true}, "visited": ["7", "8", "s2"]}')
	where = save.load_game()
	ok = _check(where.get("room") == "s2" and state.save_room == "s2" and state.health == 2 and state.abilities.imprint_unlocked and state.visited.has("8"), "a pre-merge save with room 8 visited still resumes at s2 with progression") and ok

	_write("this is not json")
	ok = _check(save.load_game().is_empty() and FileAccess.file_exists(TEMP + ".bad") and not FileAccess.file_exists(TEMP), "a damaged file is set aside as .bad and the game starts fresh") and ok

	_write('{"version": 99, "room": "1", "position": [10, 10]}')
	ok = _check(save.load_game().is_empty() and not FileAccess.file_exists(TEMP), "a save from a newer game is set aside, not overwritten") and ok

	_write('{"version": 2, "room": "1"}')
	ok = _check(save.load_game().is_empty(), "a save with no position gives no place") and ok

	save.erase()
	ok = _check(not FileAccess.file_exists(TEMP), "erase removes the save") and ok
	save.write("3", Vector2(10, 10))
	save.enabled = false
	save.erase()
	ok = _check(FileAccess.file_exists(TEMP), "erase does nothing while saving is off") and ok
	save.enabled = true
	save.erase()
	save.enabled = false
	state.reset()
	return ok


func _cap(state: Node) -> int:
	return state.TOKEN_CAP


func _write(text: String) -> void:
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
