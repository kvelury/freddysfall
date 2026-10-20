class_name ImprintReach
extends RefCounted

## Whether the player, as they are right now, can land on a platform. It tries
## a small set of jumps with the same MovementSim the player runs: input left,
## none or right, and the jump released early, part way, or not at all. Some
## plans go straight up and steer left or right a moment later. It is
## the check that tells whether the cursor is somewhere the player can get to.
## The cursor does not show the answer for now (it is always a dotted outline).

## How long the jump button is held, in physics ticks.
const HOLDS: Array[int] = [3, 8, 90]
## When a plan that starts with no steering begins to steer, in ticks.
const STEER_AT: Array[int] = [10, 20, 30]
## The platform is ignored if it is farther than this from the player.
const REACH_X := 170.0
const REACH_UP := 70.0
const REACH_DOWN := 400.0


## `rects` are the solids around the player, not including the platform.
## `hazards` kill and `triggers` are doors, which end a path. The platform
## `platform` is in the same world pixels. `grounded` is whether the player
## is standing.
static func can_land_on(cfg: MovementConfig, rects: Array[Rect2], platform: Rect2, position: Vector2, velocity: Vector2, grounded: bool, hazards: Array[Rect2] = [], triggers: Array[Rect2] = []) -> bool:
	var feet := position + Vector2(0.0, MovementSim.HALF.y)
	if absf(platform.get_center().x - position.x) > REACH_X + platform.size.x * 0.5:
		return false
	if platform.position.y < feet.y - REACH_UP or platform.position.y > feet.y + REACH_DOWN:
		return false
	var near: Array[Rect2] = [platform]
	var window := Rect2(position.x - REACH_X, position.y - REACH_UP - 60.0, REACH_X * 2.0, REACH_UP + REACH_DOWN + 60.0)
	for rect in rects:
		if rect.intersects(window):
			near.append(rect)
	var plans: Array[Dictionary] = []
	for input in [-1.0, 0.0, 1.0]:
		if grounded:
			plans.append({"input": input, "hold": 0, "jump": false, "later": NAN, "at": 0})
		for hold in HOLDS:
			plans.append({"input": input, "hold": hold, "jump": grounded, "later": NAN, "at": 0})
	for later in [-1.0, 1.0]:
		for hold in HOLDS:
			for at in STEER_AT:
				plans.append({"input": 0.0, "hold": hold, "jump": grounded, "later": later, "at": at})
	for plan in plans:
		var result := MovementSim.simulate_jump(cfg, near, position, velocity, plan["input"], plan["hold"], grounded, plan["jump"], triggers, Rect2(), hazards, [], plan["later"], plan["at"])
		if result["hazard"] or int(result["trigger"]) >= 0 or not result["landed"]:
			continue
		if _on_top(result["position"], platform):
			return true
	return false


## Whether a body resting at `at` is standing on top of `platform`.
static func _on_top(at: Vector2, platform: Rect2) -> bool:
	if absf(at.y + MovementSim.HALF.y - platform.position.y) > 0.6:
		return false
	return at.x + MovementSim.HALF.x > platform.position.x + 0.5 and at.x - MovementSim.HALF.x < platform.end.x - 0.5
