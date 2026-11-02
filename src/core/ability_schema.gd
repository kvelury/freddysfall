class_name AbilitySchema
extends RefCounted

## Pure physical domains. Editor min/max/step are separate tuning guidance.
const MAX_INTEGER := 2147483647
const LEGACY_FLOORS: Array[String] = ["air_jumps", "tongue_snap", "tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick"]
const STATS := {
	"air_jumps": {"type": "int", "default": 0, "operations": ["max"], "subsystems": ["movement", "solver"], "min": 0, "max": 2147483647},
	"tongue_unlocked": {"type": "bool", "default": false, "operations": ["unlock"], "subsystems": ["tongue", "solver"]},
	"tongue_cooldown": {"type": "float", "default": 0.05, "operations": ["min"], "subsystems": ["tongue"], "min": 0},
	"tongue_speed": {"type": "float", "default": 220.0, "operations": ["max"], "subsystems": ["tongue"], "min": 0, "exclusive_min": true},
	"tongue_snap": {"type": "float", "default": 2.0, "operations": ["max"], "subsystems": ["tongue"], "min": 1},
	"tongue_length": {"type": "float", "default": 50.0, "operations": ["max"], "subsystems": ["tongue"], "min": 0, "exclusive_min": true},
	"tongue_creep": {"type": "float", "default": 0.065, "operations": ["max"], "subsystems": ["tongue"], "min": 0},
	"tongue_creep_reach": {"type": "float", "default": 3.0, "operations": ["max"], "subsystems": ["tongue"], "min": 0},
	"tongue_ramp": {"type": "float", "default": 0.08, "operations": ["max"], "subsystems": ["tongue"], "min": 0},
	"tongue_strike": {"type": "float", "default": 3.0, "operations": ["max"], "subsystems": ["tongue"], "min": 1},
	"tongue_settle": {"type": "float", "default": 1.0, "operations": ["max"], "subsystems": ["tongue"], "min": 0},
	"tongue_stick": {"type": "float", "default": 0.1, "operations": ["max"], "subsystems": ["tongue"], "min": 0},
	"tongue_pad": {"type": "bool", "default": true, "operations": ["unlock"], "subsystems": ["tongue", "presentation"]},
	"imprint_unlocked": {"type": "bool", "default": false, "operations": ["unlock"], "subsystems": ["imprint", "solver"]},
	"imprint_width": {"type": "int", "default": 2, "operations": ["max"], "subsystems": ["imprint", "solver"], "min": 1, "max": 2147483647},
	"imprint_duration": {"type": "float", "default": 1.5, "operations": ["max"], "subsystems": ["imprint", "solver"], "min": 0, "exclusive_min": true},
	"imprint_max_active": {"type": "int", "default": 1, "operations": ["max"], "subsystems": ["imprint"], "min": 1, "max": 2147483647},
	"imprint_cooldown": {"type": "float", "default": 0.0, "operations": ["min"], "subsystems": ["imprint"], "min": 0},
	"imprint_effects": {"type": "effects", "default": [], "operations": ["add"], "subsystems": ["imprint", "solver"], "implemented": [], "planned": ["bounce"]},
}

static func check_value(stat: String, value: Variant) -> String:
	if not STATS.has(stat):
		return "Unknown ability: %s" % stat
	var domain: Dictionary = STATS[stat]
	match domain["type"]:
		"bool":
			return "Choose on or off." if not value is bool else ""
		"int", "float":
			if not (value is int or value is float) or not is_finite(float(value)):
				return "Enter a finite number."
			if domain["type"] == "int" and float(value) != floorf(float(value)):
				return "Enter a whole number."
			if value < domain["min"] or (domain.get("exclusive_min", false) and value == domain["min"]) or (domain.has("max") and value > domain["max"]):
				return "Outside the physical domain."
		"effects":
			if not value is Array:
				return "Choose supported effects."
			for effect in value:
				if not effect is String or not domain["implemented"].has(effect):
					return "Effect %s is not implemented." % str(effect)
	return ""


static func check_definition(definition: Dictionary) -> String:
	var stat = definition.get("stat")
	if not stat is String or not STATS.has(stat):
		return "Unknown ability: %s" % str(stat)
	if not STATS[stat]["operations"].has(definition.get("kind")):
		return "Incompatible operation for %s." % stat
	return ""


static func check_upgrade(definition: Dictionary, value: Variant) -> String:
	var error := check_definition(definition)
	if not error.is_empty():
		return error
	var stat: String = definition["stat"]
	if definition["kind"] == "add":
		return check_value(stat, [value])
	if definition["kind"] == "unlock" and value != true:
		return "An unlock requires true."
	return check_value(stat, value)


## Invalid or absent values use typed defaults, except explicit legacy floors.
## The old
## gun unlock survives; its untuned cooldown/speed deliberately do not migrate.
static func decode(data: Dictionary) -> Dictionary:
	var out := {}
	for stat in STATS:
		var domain: Dictionary = STATS[stat]
		var value: Variant = data.get(stat, data.get("gun_unlocked", domain["default"]) if stat == "tongue_unlocked" else domain["default"])
		if LEGACY_FLOORS.has(stat) and (value is int or value is float) and is_finite(float(value)):
			value = max(value, domain["min"])
		if not check_value(stat, value).is_empty():
			value = domain["default"]
		match domain["type"]:
			"int": value = int(value)
			"float": value = float(value)
			"effects":
				var effects: Array[String] = []
				for effect in value:
					effects.append(effect)
				value = effects
		out[stat] = value
	return out
