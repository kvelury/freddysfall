class_name Hints
extends RefCounted

## One-time tips a collectible can show in a popup when it is taken, from
## data/hints.json: each hint has a `title` and the `controls` rows (ids in
## data/controls.json) drawn under it, so a rebound key shows as rebound.
## A room names one with `hint=<id>` on a token, pickup or health legend line.

const PATH := "res://data/hints.json"

static var _hints := {}
static var _loaded := false


static func has(id: String) -> bool:
	_load()
	return _hints.has(id)


## The hint's title, or "" for an unknown id.
static func title(id: String) -> String:
	_load()
	return String((_hints.get(id, {}) as Dictionary).get("title", ""))


## The Controls rows (dictionaries) the hint shows.
static func rows(id: String) -> Array:
	_load()
	var out: Array = []
	for row_id in (_hints.get(id, {}) as Dictionary).get("controls", []):
		var row := Controls.get_row(String(row_id))
		if not row.is_empty():
			out.append(row)
	return out


## Everything wrong with the hints file. Empty means it is usable.
static func problems() -> Array[String]:
	_load()
	var errors: Array[String] = []
	for id in _hints:
		var hint = _hints[id]
		if not hint is Dictionary or String(hint.get("title", "")).is_empty():
			errors.append("Hint %s needs a title." % id)
			continue
		if not hint.get("controls") is Array or (hint["controls"] as Array).is_empty():
			errors.append("Hint %s needs controls." % id)
			continue
		for row_id in hint["controls"]:
			if Controls.get_row(String(row_id)).is_empty():
				errors.append("Hint %s uses unknown controls row %s." % [id, row_id])
	return errors


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		_hints = data
	else:
		push_error("Failed to parse %s" % PATH)
