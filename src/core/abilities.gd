class_name Abilities
extends RefCounted

## What the player can do. The values here are the starting ones; upgrades
## raise them. Each name in STATS is a stat that data/upgrades.json may name.

const STATS: Array[String] = ["imprint_width", "imprint_duration", "imprint_max_active", "imprint_effects"]

## Imprint platform width in cells.
var imprint_width := 2
## Seconds an Imprint lasts.
var imprint_duration := 4.0
var imprint_max_active := 1
## Special behaviors an Imprint has, such as "bounce".
var imprint_effects: Array[String] = []


## Applies one upgrade (see Upgrades) and says whether anything changed.
## "max" keeps the larger of the old and new value, so finding a lesser
## upgrade later never takes anything away. "add" gains an effect once.
func apply(upgrade: Dictionary, value: Variant) -> bool:
	var stat := String(upgrade["stat"])
	if upgrade["kind"] == "add":
		var effects: Array[String] = get(stat)
		if effects.has(String(value)):
			return false
		effects.append(String(value))
		return true
	var old: Variant = get(stat)
	if value <= old:
		return false
	set(stat, value)
	return true


func copy() -> Abilities:
	return Abilities.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"imprint_width": imprint_width,
		"imprint_duration": imprint_duration,
		"imprint_max_active": imprint_max_active,
		"imprint_effects": imprint_effects.duplicate(),
	}


## Reads a dictionary written by to_dict. Missing and unknown stats are left
## at their starting values or ignored, so an old save still loads.
static func from_dict(data: Dictionary) -> Abilities:
	var out := Abilities.new()
	out.imprint_width = int(data.get("imprint_width", out.imprint_width))
	out.imprint_duration = float(data.get("imprint_duration", out.imprint_duration))
	out.imprint_max_active = int(data.get("imprint_max_active", out.imprint_max_active))
	var effects = data.get("imprint_effects", [])
	if effects is Array:
		for effect in effects:
			out.imprint_effects.append(String(effect))
	return out


func describe() -> String:
	var text := "imprint %d wide, %.1f s, %d at once" % [imprint_width, imprint_duration, imprint_max_active]
	if not imprint_effects.is_empty():
		text += ", " + ", ".join(imprint_effects)
	return text
