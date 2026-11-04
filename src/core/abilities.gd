class_name Abilities
extends RefCounted

## What the player can do. The values here are the starting ones; upgrades
## raise them. The `var` lines are the stats: `stats()`, `to_dict` and
## `from_dict` follow from them, so a new stat is one line. A floor (or a
## ceiling) goes in CLAMPS. A name an old save used goes in LEGACY.

## [lowest, highest] kept when a save is read. Null is no limit on that side.
## Only the floor is held here; the dev controls hold the top of each range.
const CLAMPS := {
	"air_jumps": [0, null],
	"tongue_snap": [1.0, null],
	"tongue_creep": [0.0, null],
	"tongue_creep_reach": [0.0, null],
	"tongue_ramp": [0.0, null],
	"tongue_strike": [1.0, null],
	"tongue_settle": [0.0, null],
	"tongue_stick": [0.0, null],
	"climb_hold": [0.05, null],
	"climb_wiggle": [0.0, null],
	"climb_zip_speed": [10.0, null],
}

## A stat's old names, tried when a save has no key of its own. The gun became
## the tongue; its cooldown and shot speed were never upgraded, so they are not
## carried over.
const LEGACY := {
	"tongue_unlocked": ["gun_unlocked"],
}

## Jumps the player can make in mid-air before landing. 0 until they find double jump.
var air_jumps := 0
## Whether the player has found Tongue Lash. Until they do, `lash` does nothing.
var tongue_unlocked := false
## Seconds between lashes, counted from the tongue being back in the mouth.
var tongue_cooldown := 0.05
## How fast the tongue goes out, in pixels a second. The snap back is worked out
## from it too, so a faster tongue also snaps back faster.
var tongue_speed := 220.0
## How many times faster than `tongue_speed` the tongue comes back, on average.
## It starts back at `tongue_speed` and speeds up. 1 is a steady return.
var tongue_snap := 2.0
## How far the tongue reaches past the front of the body, in pixels. The first
## 50 is enough for every breakable wall so far; upgrades lengthen it.
var tongue_length := 50.0
## The shape of a lash is `TongueMotion`'s. These seven tune it, and the dev
## tools can change them; no room awards them. The starting values are a frog's:
## a creep, a snap, a stick on what it hit and a spring return.
## Seconds the tongue creeps at the start, and the pixels it covers doing so.
var tongue_creep := 0.065
var tongue_creep_reach := 3.0
## Seconds the speed takes to climb from the creep to the snap.
var tongue_ramp := 0.08
## How many times `tongue_speed` the tongue goes at the top of the snap.
var tongue_strike := 3.0
## 0 is the accelerating return; 1 is a spring that is fastest at once and
## eases into the mouth.
var tongue_settle := 1.0
## Seconds the tip stays on what it hit before it comes back.
var tongue_stick := 0.1
## Whether the tip is drawn as a pad (3 pixels tall) while it is stuck.
var tongue_pad := true
## Whether the player has found Tongue Climb. With it, a lash that hits a wall
## pulls Freddy to it and he hangs there by his tongue (see `MovementSim.start_climb`).
## Until then a lash only hits. No room awards it yet; the dev tools turn it on.
var tongue_climb := false
## Seconds he hangs on the wall, wiggle included, before he lets go.
var climb_hold := 0.5
## The last seconds of `climb_hold` in which he wiggles, so the player knows he is about to drop.
var climb_wiggle := 0.2
## How fast he is pulled to the wall, in pixels a second.
var climb_zip_speed := 400.0
## Whether he sticks to a breakable wall (the hit still lands) as well as to plain walls.
var climb_breakable := true
## Whether an up-lash at a ceiling pulls him up to hang there.
var climb_ceiling := true
## Whether, after dropping off because the time ran out, he must touch the ground before he can stick again.
var climb_land_to_restick := false
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
func apply(upgrade: UpgradeDef, value: Variant) -> bool:
	var stat := upgrade.stat
	if upgrade.kind == "unlock":
		if get(stat):
			return false
		set(stat, true)
		return true
	if upgrade.kind == "add":
		var effects: Array[String] = get(stat)
		if effects.has(String(value)):
			return false
		effects.append(String(value))
		return true
	if upgrade.kind == "min":
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


## The stats, in the order they are declared. A `var` on this script is a stat.
static func stats() -> Array[String]:
	var out: Array[String] = []
	for property in (Abilities as Script).get_script_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(property["name"]))
	return out


## What about these abilities changes how a body moves or what it can touch, as
## far as the solver's cache is concerned. A stat that changes a jump (a higher
## jump, a dash) has to be named in here, or a cached jump from before the
## player had it would be reused. Air jumps past the first are not modelled.
## The tongue is not here: no jump reads its length (the lash's own cache is
## keyed by it).
func movement_key() -> String:
	return "aj%d" % mini(air_jumps, 1)


func to_dict() -> Dictionary:
	var out := {}
	for stat in stats():
		var value: Variant = get(stat)
		out[stat] = (value as Array).duplicate() if value is Array else value
	return out


## Reads a dictionary written by to_dict. A missing stat stays at its starting
## value, an unknown one is ignored, and a value under its floor is lifted, so
## an old save still loads.
static func from_dict(data: Dictionary) -> Abilities:
	var out := Abilities.new()
	for stat in stats():
		var found := false
		var value: Variant = null
		if data.has(stat):
			found = true
			value = data[stat]
		else:
			for old_name in LEGACY.get(stat, []):
				if data.has(String(old_name)):
					found = true
					value = data[old_name]
					break
		if not found:
			continue
		var sample: Variant = out.get(stat)
		if sample is Array:
			if value is Array:
				var effects: Array[String] = []
				for effect in value:
					effects.append(str(effect))
				out.set(stat, effects)
			continue
		if sample is bool:
			value = bool(value)
		elif sample is int:
			value = int(value)
		elif sample is float:
			value = float(value)
		var bounds: Array = CLAMPS.get(stat, [])
		if bounds.size() == 2:
			if bounds[0] != null and value < bounds[0]:
				value = bounds[0]
			if bounds[1] != null and value > bounds[1]:
				value = bounds[1]
		out.set(stat, value)
	return out


func describe() -> String:
	var jumps := "" if air_jumps <= 0 else ("double jump, " if air_jumps == 1 else "%d air jumps, " % air_jumps)
	if tongue_unlocked:
		jumps += "tongue lash, "
	if tongue_climb:
		jumps += "tongue climb, "
	if not imprint_unlocked:
		return jumps + "imprint locked"
	var text := jumps + "imprint %d wide, %.1f s, %d at once" % [imprint_width, imprint_duration, imprint_max_active]
	if imprint_cooldown > 0.0:
		text += ", %.1f s cooldown" % imprint_cooldown
	if not imprint_effects.is_empty():
		text += ", " + ", ".join(imprint_effects)
	return text
