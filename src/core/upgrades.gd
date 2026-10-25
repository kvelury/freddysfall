class_name Upgrades
extends RefCounted

## The upgrades a pickup can give, from data/upgrades.json: upgrade id -> the
## stat it changes and how ("unlock" turns an ability on, "max" raises a number,
## "min" lowers one, "add" gains an effect), and optionally a `message` to show
## when it is taken.

const PATH := "res://data/upgrades.json"
const KINDS: Array[String] = ["unlock", "max", "min", "add"]

static var _defs := {}
static var _loaded := false
static var _problems: Array[String] = []


static func all() -> Dictionary:
	_load()
	return _defs


static func has(id: String) -> bool:
	_load()
	return _defs.has(id)


static func get_def(id: String) -> Dictionary:
	_load()
	return _defs.get(id, {})


## Everything wrong with the upgrade file. Empty means it is usable.
static func problems() -> Array[String]:
	_load()
	return _problems


## What is wrong with giving upgrade `id` the value written as `text`, or
## an empty string if nothing is.
static func check(id: String, text: String) -> String:
	var def := get_def(id)
	if def.is_empty():
		return "there is no upgrade \"%s\" (upgrades: %s)" % [id, ", ".join(all().keys())]
	if def["kind"] == "unlock":
		return "" if text.is_empty() else "upgrade %s takes no value, but was given \"%s\"" % [id, text]
	if text.is_empty():
		return "upgrade %s needs value=%s" % [id, "the name of the effect" if def["kind"] == "add" else "a number"]
	if def["kind"] == "add":
		return ""
	var sample: Variant = Abilities.new().get(String(def["stat"]))
	var valid := text.is_valid_int() if typeof(sample) == TYPE_INT else text.is_valid_float()
	if not valid:
		return "upgrade %s needs a %s value, not \"%s\"" % [id, "whole-number" if typeof(sample) == TYPE_INT else "numeric", text]
	return ""


## The value for upgrade `id` as the right type. Call check first.
static func parse_value(id: String, text: String) -> Variant:
	var def := get_def(id)
	if def["kind"] == "unlock":
		return true
	if def["kind"] == "add":
		return text
	var sample: Variant = Abilities.new().get(String(def["stat"]))
	return text.to_int() if typeof(sample) == TYPE_INT else text.to_float()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		_problems.append("Failed to parse %s" % PATH)
		return
	for id in data:
		var def = data[id]
		if not def is Dictionary or not def.get("name") is String or not def.get("stat") is String or not def.get("kind") is String:
			_problems.append("%s: upgrade \"%s\" needs a name, a stat and a kind" % [PATH, id])
			continue
		if def.has("message") and not def["message"] is String:
			_problems.append("%s: upgrade \"%s\" has a message that is not text" % [PATH, id])
			continue
		if not Abilities.STATS.has(def["stat"]):
			_problems.append("%s: upgrade \"%s\" changes \"%s\", which is not an ability (%s)" % [PATH, id, def["stat"], ", ".join(Abilities.STATS)])
			continue
		if not KINDS.has(def["kind"]):
			_problems.append("%s: upgrade \"%s\" has kind \"%s\"; it must be one of %s" % [PATH, id, def["kind"], ", ".join(KINDS)])
			continue
		_defs[String(id)] = def
