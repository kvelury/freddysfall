class_name TongueMotion
extends RefCounted

## The shape of a lash, as pure functions of time and of the tongue stats in
## `Abilities`. `TongueLash` asks them where the tip is; nothing here touches
## the scene, so the tests can walk a whole lash without a world.
##
## A frog's tongue leaves the mouth in three beats, and so does this one:
##
## 1. **Creep.** For `tongue_creep` seconds the tip moves `tongue_creep_reach`
##    pixels at a steady pace (the tongue shortens and gathers before it fires).
## 2. **Snap.** The speed climbs over `tongue_ramp` seconds to `tongue_speed`
##    times `tongue_strike` and holds there until the tip hits something or runs
##    out of `tongue_length`. The speed does not depend on the length, so a
##    longer tongue never delays a close hit.
## 3. **Return.** After `tongue_stick` seconds stuck to what it hit (none for a
##    miss), the tongue comes back in `extension / (tongue_snap * tongue_speed)`
##    seconds, so a close hit and a full reach feel alike. `tongue_settle`
##    blends the accelerating return (0) with a spring that is fastest at once
##    and eases into the mouth (1). `tongue_wobble` is a small pop-out as it
##    seats.
##
## The defaults (no creep, no ramp, a strike of 1, no settle, stick or wobble)
## give the steady way out and the accelerating snap back that came before.

## How long the tip takes to settle after it is home, in seconds.
const SEAT_TIME := 0.06
## How stiff the spring return is. The speed peaks a sixth of the way in, at
## about 2.2 times the average, then dies away.
const SPRING_K := 6.0
## Rounding slack when a time lands exactly on a phase's end.
const EPSILON := 1e-9

## The options to flip between in a dev test (see `DevSession.cycle_tongue_option`).
## Each is a set of values for the abilities named, nothing more.
const PRESETS: Array[Dictionary] = [
	{"name": "Today", "values": {
		"tongue_speed": 220.0, "tongue_snap": 3.5, "tongue_creep": 0.0, "tongue_creep_reach": 0.0,
		"tongue_ramp": 0.0, "tongue_strike": 1.0, "tongue_settle": 0.0, "tongue_stick": 0.0,
		"tongue_wobble": 0.0, "tongue_pad": false,
	}},
	{"name": "Creep & snap", "values": {
		"tongue_speed": 220.0, "tongue_snap": 2.5, "tongue_creep": 0.065, "tongue_creep_reach": 4.0,
		"tongue_ramp": 0.05, "tongue_strike": 3.9, "tongue_settle": 1.0, "tongue_stick": 0.0,
		"tongue_wobble": 0.0, "tongue_pad": false,
	}},
	{"name": "Whip", "values": {
		"tongue_speed": 220.0, "tongue_snap": 3.0, "tongue_creep": 0.05, "tongue_creep_reach": 3.0,
		"tongue_ramp": 0.03, "tongue_strike": 5.0, "tongue_settle": 1.0, "tongue_stick": 0.0,
		"tongue_wobble": 0.0, "tongue_pad": false,
	}},
	{"name": "Sticky", "values": {
		"tongue_speed": 220.0, "tongue_snap": 2.5, "tongue_creep": 0.065, "tongue_creep_reach": 4.0,
		"tongue_ramp": 0.05, "tongue_strike": 3.9, "tongue_settle": 1.0, "tongue_stick": 0.05,
		"tongue_wobble": 0.0, "tongue_pad": true,
	}},
	{"name": "Full frog", "values": {
		"tongue_speed": 220.0, "tongue_snap": 2.5, "tongue_creep": 0.065, "tongue_creep_reach": 4.0,
		"tongue_ramp": 0.05, "tongue_strike": 3.9, "tongue_settle": 1.0, "tongue_stick": 0.05,
		"tongue_wobble": 2.0, "tongue_pad": true,
	}},
]


## Pixels a second the tip travels `t` seconds after the lash left.
static func out_speed(t: float, a: Abilities) -> float:
	var peak := a.tongue_speed * a.tongue_strike
	var start := _creep_speed(a)
	if a.tongue_creep > 0.0 and t < a.tongue_creep:
		return start
	if a.tongue_ramp > 0.0 and t < a.tongue_creep + a.tongue_ramp:
		return lerpf(start, peak, (t - a.tongue_creep) / a.tongue_ramp)
	return peak


## Pixels the tip goes in the `delta` seconds from `t`: the exact area under
## `out_speed`, so a tick is the same whether the speed changes inside it or not.
static func out_distance(t: float, delta: float, a: Abilities) -> float:
	var peak := a.tongue_speed * a.tongue_strike
	var start := _creep_speed(a)
	var creep := maxf(a.tongue_creep, 0.0)
	var ramp_end := creep + maxf(a.tongue_ramp, 0.0)
	var t1 := t + delta
	var total := 0.0
	if creep > 0.0 and t < creep:
		total += start * (minf(t1, creep) - t)
	if a.tongue_ramp > 0.0 and t1 > creep and t < ramp_end:
		var lo := maxf(t, creep)
		var hi := minf(t1, ramp_end)
		total += 0.5 * (out_speed(lo, a) + out_speed(hi, a)) * (hi - lo)
	if t >= ramp_end:
		total += peak * delta
	elif t1 > ramp_end:
		total += peak * (t1 - ramp_end)
	return total


## Seconds the return takes from `extension` pixels out.
static func back_duration(extension: float, a: Abilities) -> float:
	if extension <= 0.0:
		return 0.0
	return extension / (maxf(a.tongue_snap, 1.0) * a.tongue_speed)


## The fraction of the way still out after fraction `u` of the return has gone:
## 1 at the start, 0 at the end, never rising.
static func remaining(u: float, a: Abilities) -> float:
	u = clampf(u, 0.0, 1.0)
	var p := 1.0 / maxf(a.tongue_snap, 1.0)
	# Constant acceleration from `tongue_speed`, averaging `tongue_snap` times it.
	var steady := 1.0 - (p * u + (1.0 - p) * u * u)
	var settle := clampf(a.tongue_settle, 0.0, 1.0)
	if settle <= 0.0:
		return steady
	var floor_ := (1.0 + SPRING_K) * exp(-SPRING_K)
	var spring := ((1.0 + SPRING_K * u) * exp(-SPRING_K * u) - floor_) / (1.0 - floor_)
	return lerpf(steady, spring, settle)


## Pixels the tip is out after fraction `u` of the seating time: a single small
## bump that dies away.
static func seat_offset(u: float, wobble: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return wobble * sin(PI * u) * (1.0 - u)


static func preset_count() -> int:
	return PRESETS.size()


static func preset_name(index: int) -> String:
	return String(PRESETS[index]["name"])


## A fresh copy of the values option `index` writes.
static func preset_values(index: int) -> Dictionary:
	return (PRESETS[index]["values"] as Dictionary).duplicate()


## The option whose values `abilities` (a dictionary as from `Abilities.to_dict`)
## matches exactly, or -1 if it has been tuned off every one.
static func find_preset(abilities: Dictionary) -> int:
	for i in PRESETS.size():
		var matches := true
		for stat in PRESETS[i]["values"]:
			if not abilities.has(stat) or not is_equal_approx(float(abilities[stat]), float(PRESETS[i]["values"][stat])):
				matches = false
				break
		if matches:
			return i
	return -1


static func _creep_speed(a: Abilities) -> float:
	return a.tongue_creep_reach / a.tongue_creep if a.tongue_creep > 0.0 else 0.0
