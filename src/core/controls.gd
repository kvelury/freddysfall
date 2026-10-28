class_name Controls
extends RefCounted

## The controls shown on the Controls page and in power popups, from
## data/controls.json: each row has an `id`, a `label`, the input `actions` it
## is drawn from and, for a power, the ability stat it `needs`.

const PATH := "res://data/controls.json"

static var _rows: Array = []
static var _loaded := false


static func rows() -> Array:
	_load()
	return _rows


static func get_row(id: String) -> Dictionary:
	for row: Dictionary in rows():
		if row["id"] == id:
			return row
	return {}


## Everything wrong with the controls file. Empty means it is usable.
static func problems() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for row: Dictionary in rows():
		var id := String(row.get("id", ""))
		if id.is_empty() or seen.has(id):
			errors.append("Controls row \"%s\" needs a unique id." % id)
		seen[id] = true
		if String(row.get("label", "")).is_empty():
			errors.append("Controls row %s needs a label." % id)
		if not row.get("actions") is Array or (row["actions"] as Array).is_empty():
			errors.append("Controls row %s needs actions." % id)
		else:
			for action in row["actions"]:
				if not InputMap.has_action(String(action)):
					errors.append("Controls row %s uses unknown action %s." % [id, action])
		if row.has("needs") and not Abilities.STATS.has(String(row["needs"])):
			errors.append("Controls row %s needs unknown ability %s." % [id, row["needs"]])
	return errors


## Whether the player has what row `row` needs. With no abilities (the main
## menu, where no game is loaded) only the rows that need nothing are owned.
static func owned(row: Dictionary, abilities: Abilities) -> bool:
	if not row.has("needs"):
		return true
	if abilities == null:
		return false
	var value: Variant = abilities.get(String(row["needs"]))
	if typeof(value) == TYPE_BOOL:
		return value
	return value > 0


static func visible_rows(abilities: Abilities) -> Array:
	var out: Array = []
	for row: Dictionary in rows():
		if owned(row, abilities):
			out.append(row)
	return out


## The keys of a row, in groups that are alternatives: the first binding of
## every action, then the second of every action. "move" is
## [["A", "D"], ["Left", "Right"]].
static func key_groups(row: Dictionary) -> Array:
	var per_action: Array = []
	for action in row["actions"]:
		per_action.append(InputMap.action_get_events(String(action)))
	var out: Array = []
	var most := 0
	for events: Array in per_action:
		most = maxi(most, events.size())
	for i in most:
		var group: Array = []
		for events: Array in per_action:
			if i < events.size():
				var text := _key_text(events[i])
				if not text.is_empty():
					group.append(text)
		if not group.is_empty():
			out.append(group)
	return out


static func _key_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var text := OS.get_keycode_string(code)
		return "Esc" if text == "Escape" else text
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return "MouseLeft"
	return ""


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Array:
		_rows = data
	else:
		push_error("Failed to parse %s" % PATH)
