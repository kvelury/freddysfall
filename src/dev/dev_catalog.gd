class_name DevCatalog
extends RefCounted

## Pure descriptions and validation for editable playtest state. Upgrade controls
## come from the gameplay registry; resources use the same control format.

const RESOURCES := {
	"tokens": {"name": "Tokens", "type": "int", "min": 0, "max": 3, "step": 1},
	"health": {"name": "Health pips", "type": "int", "min": 0, "step": 1},
	# The bar's length. A loadout with more pips than this raises it to match.
	"max_health": {"name": "Max pips", "type": "int", "min": 0, "step": 1},
}
## Ability names a stored loadout may still use, and what they are now.
const LEGACY_KEYS := {"gun_unlocked": "tongue_unlocked", "gun_cooldown": "tongue_cooldown", "gun_shot_speed": "tongue_speed"}
## Integers pass through cell rectangles and UI numbers. Keep them representable
## exactly, rather than accepting an overflowing float as a valid stat.
const MAX_INTEGER := 2147483647


static func controls(definitions: Dictionary = {}) -> Dictionary:
	if definitions.is_empty():
		definitions = Upgrades.all()
	var out := {}
	for id in definitions:
		var upgrade: Dictionary = definitions[id]
		if not upgrade.get("dev") is Dictionary:
			continue
		var control: Dictionary = upgrade["dev"].duplicate(true)
		control["name"] = upgrade["name"]
		out[String(upgrade["stat"])] = control
	return out


## Every upgrade and every serialized ability needs an explicit dev decision.
static func problems(definitions: Dictionary = {}, stats: Array = Abilities.STATS) -> Array[String]:
	if definitions.is_empty():
		definitions = Upgrades.all()
	var errors: Array[String] = []
	var known := controls(definitions)
	for id in definitions:
		var def: Dictionary = definitions[id]
		if not def.get("dev") is Dictionary:
			errors.append("Upgrade %s needs dev control metadata." % id)
			continue
		var control: Dictionary = def["dev"]
		if not ["bool", "int", "float", "effects", "unsupported"].has(control.get("type", "")):
			errors.append("Upgrade %s has an unknown dev control type." % id)
		if control.get("type") == "unsupported" and String(control.get("reason", "")).is_empty():
			errors.append("Upgrade %s needs a reason for missing dev support." % id)
	for stat in stats:
		if not known.has(stat):
			errors.append("Ability %s needs a dev control or an explicit exception." % stat)
		if not Abilities.new().to_dict().has(stat):
			errors.append("Ability %s is missing from serialization." % stat)
	return errors


static func defaults() -> Dictionary:
	return {"abilities": Abilities.new().to_dict(), "tokens": 0, "health": 0, "max_health": 0}


static func capture(state: Dictionary) -> Dictionary:
	return {
		"abilities": state["abilities"].duplicate(true),
		"tokens": state["tokens"],
		"health": state["health"],
		"max_health": maxi(int(state["health"]), int(state.get("max_health", 0))),
	}


## Validate the entire candidate before any live state is changed.
static func validate(loadout: Dictionary) -> String:
	if not loadout.get("abilities") is Dictionary:
		return "The loadout needs abilities."
	var known := controls()
	var values: Dictionary = loadout["abilities"]
	for stat in values:
		if not known.has(stat):
			return "Unknown ability: %s" % stat
	for stat in known:
		if not values.has(stat):
			return "Missing ability: %s" % stat
		var error := check_value(values[stat], known[stat])
		if not error.is_empty():
			return "%s: %s" % [known[stat]["name"], error]
	for key in RESOURCES:
		var error := check_value(loadout.get(key), RESOURCES[key])
		if not error.is_empty():
			return "%s: %s" % [RESOURCES[key]["name"], error]
	return ""


static func check_value(value: Variant, control: Dictionary) -> String:
	match control["type"]:
		"bool":
			return "Choose on or off." if not value is bool else ""
		"int", "float":
			if not (value is int or value is float) or not is_finite(float(value)):
				return "Enter a finite number."
			if control["type"] == "int" and (float(value) != floorf(float(value)) or float(value) > MAX_INTEGER):
				return "Enter a whole number up to %d." % MAX_INTEGER
			if value < control.get("min", 0) or (control.has("max") and value > control["max"]):
				return "Outside the allowed range."
		"effects":
			if not value is Array:
				return "Choose supported effects."
			for effect in value:
				if not effect is String or not control.get("implemented", []).has(effect):
					return "Effect %s is not implemented." % str(effect)
		"unsupported":
			return ""
	return ""


## Overlay only powers/resources, preserving captured room progression.
static func with_loadout(state: Dictionary, loadout: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	out["abilities"] = loadout["abilities"].duplicate(true)
	for key in RESOURCES:
		out[key] = int(loadout.get(key, 0))
	out["max_health"] = maxi(out["health"], out["max_health"])
	return out


## Old named loadouts pick up new defaults. Removed/unsupported entries are
## reported and dropped into a draft; selecting never applies that draft.
static func reconcile(saved: Dictionary) -> Dictionary:
	var draft := defaults()
	var warnings: Array[String] = []
	var known := controls()
	var abilities = saved.get("abilities", {})
	if not abilities is Dictionary:
		return {"error": "The stored abilities are invalid."}
	for key in abilities:
		# The gun became Tongue Lash. Its values were chosen on purpose, so they carry over.
		if LEGACY_KEYS.has(key):
			draft["abilities"][LEGACY_KEYS[key]] = abilities[key]
			continue
		if not known.has(key):
			warnings.append("Removed ability: %s" % key)
			continue
		var control: Dictionary = known[key]
		if control["type"] == "effects" and abilities[key] is Array:
			var supported: Array[String] = []
			for effect in abilities[key]:
				if control.get("implemented", []).has(effect):
					supported.append(String(effect))
				else:
					warnings.append("Unavailable effect: %s" % str(effect))
			draft["abilities"][key] = supported
		else:
			draft["abilities"][key] = abilities[key]
	for key in RESOURCES:
		if saved.has(key):
			draft[key] = saved[key]
	var error := validate(draft)
	return {"error": error, "loadout": draft, "warnings": warnings}
