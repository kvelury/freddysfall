class_name Controls
extends RefCounted

## The controls shown on the Controls page and in power popups, from
## data/controls.json: each row has an `id`, a `label`, the input `actions` it
## is drawn from and, for a power, the ability stat it `needs`.

const PATH := "res://data/controls.json"
## The `device` of every event built from a binding: any (Godot's -1), as the
## events in project.godot are. An event that kept the default 0 would answer
## only the first pad, so a second one would do nothing.
const ANY_DEVICE := -1

static var _rows: Array = []
static var _loaded := false

## The kind of input last used, "keyboard" or "controller". The Controls
## screens and the popup prompts show that kind. InputBindings keeps it up to
## date; it is a plain value here so this file needs no autoload.
static var device := "keyboard"
## The system's name for the pad last used, which picks its button labels.
static var pad_name := ""


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
		if row.has("needs") and not Abilities.stats().has(String(row["needs"])):
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


## The prompt that closes a popup: any key, or any button when a controller
## is the last thing used.
static func press_any() -> String:
	return "Press any button to continue" if device == "controller" else "Press any key to continue"


## The keys of a row, in groups that are alternatives: the first binding of
## every action, then the second of every action. "move" is
## [["A", "D"], ["Left", "Right"]]. `kind` is "keyboard" or "controller"; the
## default is the kind last used. A controller's two directions of one stick
## are one cap, so move is [["LS"], ["Left", "Right"]] there (the D-pad).
static func key_groups(row: Dictionary, kind := "") -> Array:
	if kind.is_empty():
		kind = device
	if bool(row.get("combo", false)):
		return _combo_groups(row, kind)
	var per_action: Array = []
	for action in row["actions"]:
		per_action.append(_events_of(String(action), kind))
	var out: Array = []
	var most := 0
	for events: Array in per_action:
		most = maxi(most, events.size())
	for i in most:
		var group: Array = []
		var stick := _shared_stick(per_action, i)
		if stick >= 0:
			group.append("L-Stick" if stick <= JOY_AXIS_LEFT_Y else "R-Stick")
		else:
			for events: Array in per_action:
				if i < events.size():
					var text := _key_text(events[i], kind)
					if not text.is_empty():
						group.append(text)
		if not group.is_empty():
			out.append(group)
	return out


## The events of `action` that `kind` of device sends.
static func _events_of(action: String, kind: String) -> Array:
	var out: Array = []
	for event in InputMap.action_get_events(action):
		if not _key_text(event, kind).is_empty():
			out.append(event)
	return out


## The stick axis that binding `i` of every action in `per_action` is a
## direction of (two or more actions, all on one axis), or -1.
static func _shared_stick(per_action: Array, i: int) -> int:
	if per_action.size() < 2:
		return -1
	var found := -1
	for events: Array in per_action:
		if i >= events.size() or not events[i] is InputEventJoypadMotion:
			return -1
		var axis: int = events[i].axis
		if axis > JOY_AXIS_RIGHT_Y or (found >= 0 and axis != found):
			return -1
		found = axis
	return found


## A row whose keys are pressed together (`"combo": true`): each binding of its
## first action with the first binding of every other action, so look up and lash
## are [["W", "X"], ["Up", "X"]].
static func _combo_groups(row: Dictionary, kind: String) -> Array:
	var actions: Array = row["actions"]
	var rest: Array[String] = []
	for i in range(1, actions.size()):
		var events := _events_of(String(actions[i]), kind)
		var text := _key_text(events[0], kind) if not events.is_empty() else ""
		if not text.is_empty():
			rest.append(text)
	var out: Array = []
	for event in _events_of(String(actions[0]), kind):
		var first := _key_text(event, kind)
		if first.is_empty():
			continue
		var group: Array = [first]
		group.append_array(rest)
		out.append(group)
	return out


## Whether `event` dismisses a popup (the power popup, Game Over): any key or
## gamepad button going down. The mouse never does, because it is only for
## menus. Function keys (the dev tools: F2, F3, F4, F7) and modifier keys on
## their own do not, so a popup can be open while a tool is used.
static func dismisses(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventJoypadButton:
		return true
	if not event is InputEventKey:
		return false
	var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if code >= KEY_F1 and code <= KEY_F35:
		return false
	return not code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK, KEY_NONE]


## The cap text for `event` as `kind` of device ("keyboard" or "controller"),
## or "" if that device does not send it.
static func _key_text(event: InputEvent, kind := "keyboard") -> String:
	if kind == "controller":
		var family := PadLabels.family(pad_name)
		if event is InputEventJoypadButton:
			return PadLabels.button(family, event.button_index)
		if event is InputEventJoypadMotion:
			return PadLabels.axis(family, event.axis, 1 if event.axis_value >= 0.0 else -1)
		return ""
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var text := OS.get_keycode_string(code)
		return "Esc" if text == "Escape" else text
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return "MouseLeft"
	return ""


## The text on the cap of a stored binding (see `binding_from_event`).
static func binding_text(binding: Dictionary) -> String:
	var event := binding_event(binding)
	if event == null:
		return ""
	return _key_text(event, "keyboard" if binding.get("t") == "key" else "controller")


## The kind of device a binding belongs to, "keyboard" or "controller".
static func binding_kind(binding: Dictionary) -> String:
	return "keyboard" if binding.get("t") == "key" else "controller"


## A binding is a plain dictionary so it saves as JSON: `{"t": "key", "code":
## <physical keycode>}`, `{"t": "button", "index": <JoyButton>}` or `{"t":
## "axis", "axis": <JoyAxis>, "sign": -1 or 1}`. The input event it stands for,
## or null if the dictionary is not a binding.
static func binding_event(binding: Dictionary) -> InputEvent:
	match binding.get("t"):
		"key":
			var key := InputEventKey.new()
			key.device = ANY_DEVICE
			key.physical_keycode = int(binding["code"]) as Key
			return key
		"button":
			var button := InputEventJoypadButton.new()
			button.device = ANY_DEVICE
			button.button_index = int(binding["index"]) as JoyButton
			return button
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.device = ANY_DEVICE
			motion.axis = int(binding["axis"]) as JoyAxis
			motion.axis_value = float(int(binding["sign"]))
			return motion
	return null


## The binding an input event would make, or {} if it cannot be bound: a key
## that is Escape, a function key (the dev tools), a modifier or a lock; the
## Start and Back/Select buttons (Start is pause and Back opens the dev tools);
## a stick or trigger pushed less than 0.6; a trigger pulled the wrong way. A
## key or button must be going down, not repeating.
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return {}
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_ESCAPE or code >= KEY_F1 and code <= KEY_F35:
			return {}
		if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK, KEY_NONE]:
			return {}
		return {"t": "key", "code": int(code)}
	if event is InputEventJoypadButton:
		if not event.pressed or event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_GUIDE]:
			return {}
		return {"t": "button", "index": int(event.button_index)}
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) < 0.6 or event.axis > JOY_AXIS_TRIGGER_RIGHT:
			return {}
		var sign := 1 if event.axis_value > 0.0 else -1
		if event.axis >= JOY_AXIS_TRIGGER_LEFT and sign < 0:
			return {}
		return {"t": "axis", "axis": int(event.axis), "sign": sign}
	return {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Array:
		_rows = data
	else:
		push_error("Failed to parse %s" % PATH)
