extends SceneTree

## Room 7's title card: the data, that it shows as the player drops in and is
## gone as they land, that it shows once, and that a pause freezes it.


func _initialize() -> void:
	# A script error inside a coroutine leaves the test waiting forever.
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)
	_run()


func _run() -> void:
	var data := root.get_node("WorldData")
	data.ensure_loaded()
	var ok := _check(data.titles.has("7") and data.titles["7"]["text"] == "Freddy's Fall", "room 7 has the title card Freddy's Fall")
	var problems: Array[String] = []
	ok = _check(data.read_title("Freddy", "7", problems).is_empty() and problems.size() == 1, "a title that is not a dictionary is an error") and ok
	ok = _check(data.read_title({"text": "", "hold": 1}, "7", problems).is_empty() and problems.size() == 2, "a title with no text is an error") and ok
	ok = _check(data.read_title({"text": "A", "hold": 0}, "7", problems).is_empty() and problems.size() == 3, "a title that holds for no time is an error") and ok
	ok = _check(data.read_title({"text": "A", "hold": 1.5}, "7", problems) == {"text": "A", "hold": 1.5} and problems.size() == 3, "a good title is read") and ok

	root.get_node("GameState").reset()
	var world := (load("res://src/world/world.tscn") as PackedScene).instantiate()
	world.start_override = "6"
	root.add_child(world)
	await process_frame
	# A room test is isolated and leaves the flags alone; this one checks a normal game.
	root.get_node("DevSession").reset_to_normal()
	var player: Player = world.get_node("Player")
	var card: TitleCard = world.title_card
	player.scripted = true
	ok = _check(not card.label.visible, "starting in room 6 shows no card") and ok

	# The first drop: from rest in room 6 down the door to the shaft's floor.
	var fall: Dictionary = await _drop(world)
	var total := TitleCard.total(float(data.titles["7"]["hold"]))
	print("measured: %.3f s from entering room 7 to landing; the card lasts %.3f s" % [fall["seconds"], total])
	ok = _check(fall["entered"], "the player drops into room 7") and ok
	ok = _check(fall["shown_on_entry"], "the card is showing as the player enters") and ok
	ok = _check(absf(total - fall["seconds"]) <= 0.1, "the card lasts as long as the fall (%.3f s against %.3f s)" % [total, fall["seconds"]]) and ok
	ok = _check(fall["hidden_after"], "the card is gone within 6 ticks of landing") and ok
	ok = _check(root.get_node("GameState").has_flag("title:7"), "the card is remembered in the save") and ok

	# Dropping again shows nothing.
	world.warp_to("6")
	var again: Dictionary = await _drop(world)
	ok = _check(again["entered"] and not again["shown_on_entry"], "a second drop shows no card") and ok

	# A pause freezes it.
	card.show_title("Test", 1.0)
	await physics_frame
	await physics_frame
	world.acquire_modal("test")
	var before := card.label.modulate.a
	for i in 30:
		await process_frame
	ok = _check(card.label.modulate.a == before and before > 0.0, "a pause freezes the card (%.3f)" % before) and ok
	world.release_modal("test")

	world.free()
	print("TITLE %s" % ("pass" if ok else "fail"))
	quit(0 if ok else 1)


## Lets the player fall from rest in room 6 into room 7 and down to its floor.
## Returns whether they arrived, whether the card was showing on the tick they
## did, the seconds from then to landing, and whether the card was gone six
## ticks after.
func _drop(world: Node) -> Dictionary:
	var player: Player = world.get_node("Player")
	var room: Room = world.current
	player.scripted_x = 0.0
	player.place(room.position + Vector2(75, 165), room.world_rects())
	player.velocity = Vector2.ZERO
	var out := {"entered": false, "shown_on_entry": false, "seconds": 0.0, "hidden_after": false}
	var ticks := 0
	for i in 600:
		await physics_frame
		if not out["entered"]:
			if root.get_node("GameState").current_room_id == "7":
				out["entered"] = true
				out["shown_on_entry"] = world.title_card.label.visible
		else:
			ticks += 1
			if player.is_on_floor() and not world.is_busy():
				break
	out["seconds"] = float(ticks) / 60.0
	for i in 6:
		await physics_frame
	out["hidden_after"] = not world.title_card.label.visible
	return out


func _check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	return cond
