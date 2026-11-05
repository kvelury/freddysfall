extends Node

## The player's controls: what each gameplay action is bound to on the keyboard
## and on a controller, and the changes the player has made in Settings.
##
## The defaults are what project.godot's [input] section says; they are copied
## at boot. The player's changes are `user://controls.json`, applied over them.
## It is a preference, not progress: it is not the game save, so New Game and
## `Save.erase()` leave it alone and a dev test reads and writes it as usual.
## On the web, closing the file syncs it to IndexedDB, as the save does.
##
## Each action keeps up to SLOTS bindings per kind of device. Escape is always
## pause (and cancel), the function keys are the dev tools and Start / Back are
## pause and the dev tools, so none of those can be bound.

signal device_changed
signal bindings_changed

const VERSION := 1
const SLOTS := 2
const KINDS := ["keyboard", "controller"]
## The actions the player can rebind, in the order Settings lists them. The
## map's zoom (`FOLLOWS`) is not one of them: it moves with look up and down.
const ACTIONS := ["move_left", "move_right", "look_up", "look_down", "jump", "lash", "map", "pause"]
const LABELS := {
	"move_left": "Move left",
	"move_right": "Move right",
	"look_up": "Look up",
	"look_down": "Look down",
	"jump": "Jump",
	"lash": "Tongue lash / climb",
	"map": "Map (hold)",
	"pause": "Pause",
}
const FOLLOWS := {"map_zoom_in": "look_up", "map_zoom_out": "look_down"}
## Bindings that are always there and cannot be changed.
const FIXED := {"pause": {"keyboard": [{"t": "key", "code": KEY_ESCAPE}]}}

## Whether changes are written to disk. A test turns it off.
var enabled := true
var path := "user://controls.json"

var _defaults := {}
var _current := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_defaults = _from_input_map()
	_current = _copy(_defaults)
	load_file()


## The last kind of device the player used, which Controls shows.
func device() -> String:
	return Controls.device


## The player's bindings of `action` for `kind` of device ("keyboard" or
## "controller"), in slot order. A copy.
func get_bindings(action: String, kind: String) -> Array:
	return (_current[action][kind] as Array).duplicate(true)


## The bindings that cannot be changed and are shown before the slots.
func fixed(action: String, kind: String) -> Array:
	return (FIXED.get(action, {}).get(kind, []) as Array).duplicate(true)


## Puts `binding` in slot `slot` of `action` for the device it belongs to (a
## slot one past the last adds a binding). If another action has it, the two
## swap, or it is taken if that action has another; the answer says which.
## `{"ok": bool, "note": String}`. A change is applied and saved at once.
func rebind(action: String, slot: int, binding: Dictionary) -> Dictionary:
	if not ACTIONS.has(action) or slot < 0 or slot >= SLOTS or _clean(binding) != binding:
		return {"ok": false, "note": "That cannot be bound"}
	var kind := Controls.binding_kind(binding)
	var mine: Array = _current[action][kind]
	slot = mini(slot, mine.size())
	var old: Dictionary = mine[slot] if slot < mine.size() else {}
	if binding == old:
		return {"ok": true, "note": ""}
	var at := mine.find(binding)
	if at >= 0:
		# Already on this action: the two slots swap.
		if old.is_empty():
			return {"ok": false, "note": "%s already has that" % LABELS[action]}
		mine[at] = old
		mine[slot] = binding
		_changed()
		return {"ok": true, "note": ""}
	var note := ""
	for other: String in ACTIONS:
		var theirs: Array = _current[other][kind]
		var found := theirs.find(binding)
		if other == action or found < 0:
			continue
		if not old.is_empty():
			theirs[found] = old
			note = "Swapped with %s" % LABELS[other]
		elif theirs.size() > 1:
			theirs.remove_at(found)
			note = "Taken from %s" % LABELS[other]
		else:
			return {"ok": false, "note": "%s needs it" % LABELS[other]}
	if slot < mine.size():
		mine[slot] = binding
	else:
		mine.append(binding)
	_changed()
	return {"ok": true, "note": note}


## Puts every action's bindings for `kind` back to the defaults.
func reset(kind: String) -> void:
	for action: String in ACTIONS:
		_current[action][kind] = (_defaults[action][kind] as Array).duplicate(true)
	_changed()


func is_default(kind: String) -> bool:
	for action: String in ACTIONS:
		if _current[action][kind] != _defaults[action][kind]:
			return false
	return true


## Applies the bindings to the InputMap, tells Settings, and saves.
func _changed() -> void:
	_apply()
	save()
	bindings_changed.emit()


func _apply() -> void:
	for action: String in ACTIONS:
		InputMap.action_erase_events(action)
		for kind: String in KINDS:
			for binding: Dictionary in fixed(action, kind) + (_current[action][kind] as Array):
				InputMap.action_add_event(action, Controls.binding_event(binding))
	for zoom: String in FOLLOWS:
		InputMap.action_erase_events(zoom)
		for event in InputMap.action_get_events(FOLLOWS[zoom]):
			InputMap.action_add_event(zoom, event.duplicate())


## What project.godot binds, as bindings. The fixed ones are left out.
func _from_input_map() -> Dictionary:
	var out := {}
	for action: String in ACTIONS:
		out[action] = {"keyboard": [], "controller": []}
		for event in InputMap.action_get_events(action):
			var binding := _event_binding(event)
			if binding.is_empty() or binding in fixed(action, Controls.binding_kind(binding)):
				continue
			out[action][Controls.binding_kind(binding)].append(binding)
	return out


## The binding for an event in the project's input map (which, unlike a
## captured event, is not "pressed").
func _event_binding(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return {"t": "key", "code": int(code)}
	if event is InputEventJoypadButton:
		return {"t": "button", "index": int(event.button_index)}
	if event is InputEventJoypadMotion:
		return {"t": "axis", "axis": int(event.axis), "sign": 1 if event.axis_value >= 0.0 else -1}
	return {}


func _copy(from: Dictionary) -> Dictionary:
	return from.duplicate(true)


func save() -> bool:
	if not enabled:
		return false
	var data := {"version": VERSION, "bindings": _current}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save the controls to %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	# On the web, closing a user:// file is what has it synced to IndexedDB.
	file.close()
	return true


## Reads the player's changes over the defaults. A file that is missing or
## unreadable is ignored; an action or device missing from it, or with a
## binding that cannot be one, keeps its default.
func load_file() -> void:
	_current = _copy(_defaults)
	if enabled and FileAccess.file_exists(path):
		var json := JSON.new()
		var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
		if data is Dictionary and int(data.get("version", 0)) == VERSION and data.get("bindings") is Dictionary:
			for action: String in ACTIONS:
				var saved: Variant = data["bindings"].get(action)
				if saved is Dictionary:
					for kind: String in KINDS:
						var list := _valid(saved.get(kind), kind)
						if not list.is_empty():
							_current[action][kind] = list
	_resolve_clashes()
	_apply()
	bindings_changed.emit()


## The bindings in `raw` if it is a usable list for `kind`, else [].
func _valid(raw: Variant, kind: String) -> Array:
	var out: Array = []
	if not raw is Array or (raw as Array).is_empty() or (raw as Array).size() > SLOTS:
		return out
	for item in raw:
		if not item is Dictionary:
			return []
		var binding := _clean(item)
		if binding.is_empty() or Controls.binding_kind(binding) != kind or binding in out:
			return []
		out.append(binding)
	return out


## A binding read back from JSON (its numbers are floats), or {} if it is not
## one the player could have made.
func _clean(item: Dictionary) -> Dictionary:
	var binding := {}
	match item.get("t"):
		"key":
			binding = {"t": "key", "code": int(item.get("code", 0))}
		"button":
			binding = {"t": "button", "index": int(item.get("index", -1))}
		"axis":
			binding = {"t": "axis", "axis": int(item.get("axis", -1)), "sign": 1 if float(item.get("sign", 0)) > 0.0 else -1}
	if binding.is_empty():
		return {}
	var event := Controls.binding_event(binding)
	var again := Controls.binding_from_event(_pressed(event))
	return binding if again == binding else {}


## `event` as it would arrive when the player pressed it, so it passes the
## same checks as a captured one.
func _pressed(event: InputEvent) -> InputEvent:
	if event is InputEventKey or event is InputEventJoypadButton:
		event.pressed = true
	elif event is InputEventJoypadMotion:
		event.axis_value = signf(event.axis_value)
	return event


## A file edited by hand could give one input to two actions, which would make
## both fire. The action earlier in ACTIONS keeps it and the later one goes back
## to its default for that device.
func _resolve_clashes() -> void:
	for kind: String in KINDS:
		var taken := []
		for action: String in ACTIONS:
			for binding: Dictionary in _current[action][kind]:
				if binding in taken:
					_current[action][kind] = (_defaults[action][kind] as Array).duplicate(true)
					break
			taken.append_array(_current[action][kind])


## Follows the last device used, which decides whether the screens show keys or
## buttons. The mouse does not count: it is only for menus.
func _input(event: InputEvent) -> void:
	var kind := ""
	if event is InputEventKey and event.pressed:
		kind = "keyboard"
	elif event is InputEventJoypadButton and event.pressed:
		kind = "controller"
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.6:
		kind = "controller"
	if kind.is_empty():
		return
	var name_before := Controls.pad_name
	if kind == "controller":
		Controls.pad_name = Input.get_joy_name(event.device)
	if kind != Controls.device or name_before != Controls.pad_name:
		Controls.device = kind
		device_changed.emit()
