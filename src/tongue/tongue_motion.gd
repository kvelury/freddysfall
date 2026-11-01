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
##    and eases into the mouth (1).
##
## The starting values are the lash the user chose by playing five options in
## the dev tools. With no creep, no ramp, a strike of 1, no settle and no stick
## (and a snap of 3.5) it is the steady way out and accelerating snap back of
## PR #67, which the tests keep as a second case.

## How stiff the spring return is. The speed peaks a sixth of the way in, at
## about 2.2 times the average, then dies away.
const SPRING_K := 6.0
## Rounding slack when a time lands exactly on a phase's end.
const EPSILON := 1e-9

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


static func _creep_speed(a: Abilities) -> float:
	return a.tongue_creep_reach / a.tongue_creep if a.tongue_creep > 0.0 else 0.0
