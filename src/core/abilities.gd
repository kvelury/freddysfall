class_name Abilities
extends RefCounted

## What the player can do. The values here are the starting ones; upgrades
## raise them. Each name in STATS is a stat that data/upgrades.json may name.

const STATS: Array[String] = ["air_jumps", "gun_unlocked", "gun_cooldown", "gun_shot_speed", "imprint_unlocked", "imprint_width", "imprint_duration", "imprint_max_active", "imprint_cooldown", "imprint_effects"]

## Jumps the player can make in mid-air before landing. 0 until they find double jump.
var air_jumps := 0
## Whether the player has found the gun. Until they do, `shoot` does nothing.
var gun_unlocked := false
## Seconds between shots.
var gun_cooldown := 0.2
## How fast a shot flies, in pixels a second.
var gun_shot_speed := 260.0
## Whether the player has found Imprint. Until they do, the cursor is just a cursor.
var imprint_unlocked := false
## Imprint platform width in cells.
var imprint_width := 2
## Seconds an Imprint lasts.
var imprint_duration := 1.5
var imprint_max_active := 1
## Seconds after a platform breaks before another may be placed. 0 is off.
var imprint_cooldown := 0.0
## Special behaviors an Imprint has, such as "bounce".
var imprint_effects: Array[String] = []


## Applies one upgrade (see Upgrades) and says whether anything changed.
## "unlock" turns a yes-or-no ability on. "max" keeps the larger of the old and new value, so finding a lesser
## upgrade later never takes anything away. "min" keeps the smaller, for a number where lower is better.
## "add" gains an effect once.
func apply(upgrade: Dictionary, value: Variant) -> bool:
	var stat := String(upgrade["stat"])
	if upgrade["kind"] == "unlock":
		if get(stat):
			return false
		set(stat, true)
		return true
	if upgrade["kind"] == "add":
		var effects: Array[String] = get(stat)
		if effects.has(String(value)):
			return false
		effects.append(String(value))
		return true
	if upgrade["kind"] == "min":
		var current: Variant = get(stat)
		if value >= current:
			return false
		set(stat, value)
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
		"air_jumps": air_jumps,
		"gun_unlocked": gun_unlocked,
		"gun_cooldown": gun_cooldown,
		"gun_shot_speed": gun_shot_speed,
		"imprint_unlocked": imprint_unlocked,
		"imprint_width": imprint_width,
		"imprint_duration": imprint_duration,
		"imprint_max_active": imprint_max_active,
		"imprint_cooldown": imprint_cooldown,
		"imprint_effects": imprint_effects.duplicate(),
	}


## Reads a dictionary written by to_dict. Missing and unknown stats are left
## at their starting values or ignored, so an old save still loads.
static func from_dict(data: Dictionary) -> Abilities:
	var out := Abilities.new()
	out.air_jumps = maxi(0, int(data.get("air_jumps", out.air_jumps)))
	out.gun_unlocked = bool(data.get("gun_unlocked", out.gun_unlocked))
	out.gun_cooldown = float(data.get("gun_cooldown", out.gun_cooldown))
	out.gun_shot_speed = float(data.get("gun_shot_speed", out.gun_shot_speed))
	out.imprint_unlocked = bool(data.get("imprint_unlocked", out.imprint_unlocked))
	out.imprint_width = int(data.get("imprint_width", out.imprint_width))
	out.imprint_duration = float(data.get("imprint_duration", out.imprint_duration))
	out.imprint_max_active = int(data.get("imprint_max_active", out.imprint_max_active))
	out.imprint_cooldown = float(data.get("imprint_cooldown", out.imprint_cooldown))
	var effects = data.get("imprint_effects", [])
	if effects is Array:
		for effect in effects:
			out.imprint_effects.append(String(effect))
	return out


func describe() -> String:
	var jumps := "" if air_jumps <= 0 else ("double jump, " if air_jumps == 1 else "%d air jumps, " % air_jumps)
	if gun_unlocked:
		jumps += "gun, "
	if not imprint_unlocked:
		return jumps + "imprint locked"
	var text := jumps + "imprint %d wide, %.1f s, %d at once" % [imprint_width, imprint_duration, imprint_max_active]
	if imprint_cooldown > 0.0:
		text += ", %.1f s cooldown" % imprint_cooldown
	if not imprint_effects.is_empty():
		text += ", " + ", ".join(imprint_effects)
	return text
