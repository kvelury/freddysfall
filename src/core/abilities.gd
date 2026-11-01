class_name Abilities
extends RefCounted

## What the player can do. The values here are the starting ones; upgrades
## raise them. Each name in STATS is a stat that data/upgrades.json may name.

const STATS: Array[String] = ["air_jumps", "tongue_unlocked", "tongue_cooldown", "tongue_speed", "tongue_snap", "tongue_length", "tongue_creep", "tongue_creep_reach", "tongue_ramp", "tongue_strike", "tongue_settle", "tongue_stick", "tongue_wobble", "tongue_pad", "imprint_unlocked", "imprint_width", "imprint_duration", "imprint_max_active", "imprint_cooldown", "imprint_effects"]

## Jumps the player can make in mid-air before landing. 0 until they find double jump.
var air_jumps := 0
## Whether the player has found Tongue Lash. Until they do, `lash` does nothing.
var tongue_unlocked := false
## Seconds between lashes, counted from the tongue being back in the mouth.
var tongue_cooldown := 0.15
## How fast the tongue goes out, in pixels a second. The snap back is worked out
## from it too, so a faster tongue also snaps back faster.
var tongue_speed := 220.0
## How many times faster than `tongue_speed` the tongue comes back, on average.
## It starts back at `tongue_speed` and speeds up. 1 is a steady return.
var tongue_snap := 3.5
## How far the tongue reaches past the front of the body, in pixels. The first
## 50 is enough for every breakable wall so far; upgrades lengthen it.
var tongue_length := 50.0
## The shape of a lash is `TongueMotion`'s. These eight tune it; their values
## are the steady way out and accelerating snap back that came before, and no
## room awards them (only the dev tools change them).
## Seconds the tongue creeps at the start, and the pixels it covers doing so.
var tongue_creep := 0.0
var tongue_creep_reach := 0.0
## Seconds the speed takes to climb from the creep to the snap.
var tongue_ramp := 0.0
## How many times `tongue_speed` the tongue goes at the top of the snap.
var tongue_strike := 1.0
## 0 is the accelerating return; 1 is a spring that is fastest at once and
## eases into the mouth.
var tongue_settle := 0.0
## Seconds the tip stays on what it hit before it comes back.
var tongue_stick := 0.0
## Pixels the tip pops out as it seats.
var tongue_wobble := 0.0
## Whether the tip is drawn as a pad (3 pixels tall) while it is stuck.
var tongue_pad := false
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
		"tongue_unlocked": tongue_unlocked,
		"tongue_cooldown": tongue_cooldown,
		"tongue_speed": tongue_speed,
		"tongue_snap": tongue_snap,
		"tongue_length": tongue_length,
		"tongue_creep": tongue_creep,
		"tongue_creep_reach": tongue_creep_reach,
		"tongue_ramp": tongue_ramp,
		"tongue_strike": tongue_strike,
		"tongue_settle": tongue_settle,
		"tongue_stick": tongue_stick,
		"tongue_wobble": tongue_wobble,
		"tongue_pad": tongue_pad,
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
	# A save from the gun's days keeps the power it found. Its cooldown and shot
	# speed are dropped: no upgrade ever changed them.
	out.tongue_unlocked = bool(data.get("tongue_unlocked", data.get("gun_unlocked", out.tongue_unlocked)))
	out.tongue_cooldown = float(data.get("tongue_cooldown", out.tongue_cooldown))
	out.tongue_speed = float(data.get("tongue_speed", out.tongue_speed))
	out.tongue_snap = maxf(1.0, float(data.get("tongue_snap", out.tongue_snap)))
	out.tongue_length = float(data.get("tongue_length", out.tongue_length))
	# Only the floor is held here; the dev controls hold the top of each range.
	out.tongue_creep = maxf(0.0, float(data.get("tongue_creep", out.tongue_creep)))
	out.tongue_creep_reach = maxf(0.0, float(data.get("tongue_creep_reach", out.tongue_creep_reach)))
	out.tongue_ramp = maxf(0.0, float(data.get("tongue_ramp", out.tongue_ramp)))
	out.tongue_strike = maxf(1.0, float(data.get("tongue_strike", out.tongue_strike)))
	out.tongue_settle = clampf(float(data.get("tongue_settle", out.tongue_settle)), 0.0, 1.0)
	out.tongue_stick = maxf(0.0, float(data.get("tongue_stick", out.tongue_stick)))
	out.tongue_wobble = maxf(0.0, float(data.get("tongue_wobble", out.tongue_wobble)))
	out.tongue_pad = bool(data.get("tongue_pad", out.tongue_pad))
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
	if tongue_unlocked:
		jumps += "tongue lash, "
	if not imprint_unlocked:
		return jumps + "imprint locked"
	var text := jumps + "imprint %d wide, %.1f s, %d at once" % [imprint_width, imprint_duration, imprint_max_active]
	if imprint_cooldown > 0.0:
		text += ", %.1f s cooldown" % imprint_cooldown
	if not imprint_effects.is_empty():
		text += ", " + ", ".join(imprint_effects)
	return text
