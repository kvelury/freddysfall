class_name MovementSim
extends RefCounted

## One movement step shared by the player and the jump tests.
## Imprint reachability should call simulate_jump() against a room's merged
## rectangles instead of copying these formulas.


static func integrate(
	cfg: MovementConfig,
	velocity: Vector2,
	grounded: bool,
	coyote: float,
	buffer: float,
	launched: bool,
	cut: bool,
	input_x: float,
	jump_pressed: bool,
	jump_held: bool,
	delta: float,
	out: Dictionary
) -> void:
	var target := 0.0
	var accel := cfg.ground_friction if grounded else cfg.air_friction
	if absf(input_x) > 0.01:
		target = input_x * cfg.run_speed
		accel = cfg.ground_accel if grounded else cfg.air_accel
	velocity.x = move_toward(velocity.x, target, accel * delta)

	if grounded:
		coyote = cfg.coyote_time
	else:
		coyote = maxf(0.0, coyote - delta)
	if jump_pressed:
		buffer = cfg.jump_buffer
	else:
		buffer = maxf(0.0, buffer - delta)

	var jumped := false
	if buffer > 0.0 and coyote > 0.0:
		velocity.y = -cfg.jump_speed
		jumped = true
		launched = true
		cut = false
		coyote = 0.0
		buffer = 0.0
	else:
		if launched and not jump_held and velocity.y < 0.0 and not cut:
			velocity.y *= cfg.jump_cut
			cut = true
		var scale := 1.0
		if not grounded:
			if absf(velocity.y) < cfg.apex_threshold:
				scale = cfg.apex_gravity_scale
			elif velocity.y > 0.0:
				scale = cfg.fall_gravity_scale
		velocity.y += cfg.gravity * scale * delta
		velocity.y = minf(velocity.y, cfg.max_fall_speed)
		if grounded:
			launched = false
			cut = false

	out["velocity"] = velocity
	out["coyote"] = coyote
	out["buffer"] = buffer
	out["launched"] = launched
	out["cut"] = cut
	out["jumped"] = jumped


static func resolve(position: Vector2, velocity: Vector2, rects: Array, delta: float, half: Vector2) -> Dictionary:
	var pos := position
	var vel := velocity
	pos.x += vel.x * delta
	for rect in rects:
		var block: Rect2 = rect
		if _overlaps(pos, half, block):
			if vel.x > 0.0:
				pos.x = block.position.x - half.x
			elif vel.x < 0.0:
				pos.x = block.end.x + half.x
			vel.x = 0.0
	pos.y += vel.y * delta
	var grounded := false
	var floor := Rect2()
	for rect in rects:
		var block: Rect2 = rect
		if _overlaps(pos, half, block):
			if vel.y >= 0.0:
				pos.y = block.position.y - half.y
				vel.y = 0.0
				grounded = true
				floor = block
			else:
				pos.y = block.end.y + half.y
				vel.y = 0.0
	return {
		"position": pos,
		"velocity": vel,
		"grounded": grounded,
		"floor": floor,
	}


## Runs one input plan from a standing start until the body lands, touches a
## trigger, or leaves `bounds`. `jump` false walks (or drops) without jumping.
## `triggers` are pixel rects; the result's "trigger" is the index of the first
## one touched, or -1. An empty `bounds` means no limit.
static func simulate_jump(
	cfg: MovementConfig,
	rects: Array,
	start_position: Vector2,
	start_velocity: Vector2,
	input_x: float,
	hold_frames: int,
	grounded_start: bool = true,
	jump: bool = true,
	triggers: Array = [],
	bounds: Rect2 = Rect2()
) -> Dictionary:
	var pos := start_position
	var vel := start_velocity
	var grounded := grounded_start
	var coyote := cfg.coyote_time if grounded_start else 0.0
	var buffer := 0.0
	var launched := false
	var cut := false
	var delta := 1.0 / 60.0
	var half := Vector2(float(Grid.CELL) * 0.5, float(Grid.CELL) * 0.5)
	var out := {}
	var min_feet := pos.y + half.y
	var landed := false
	var airborne := false
	var trigger := -1
	var floor := Rect2()
	for frame in 180:
		integrate(
			cfg, vel, grounded, coyote, buffer, launched, cut,
			input_x, jump and frame == 0, frame < hold_frames, delta, out
		)
		vel = out["velocity"]
		coyote = out["coyote"]
		buffer = out["buffer"]
		launched = out["launched"]
		cut = out["cut"]
		var resolved := resolve(pos, vel, rects, delta, half)
		pos = resolved["position"]
		vel = resolved["velocity"]
		grounded = resolved["grounded"]
		min_feet = minf(min_feet, pos.y + half.y)
		if not grounded:
			airborne = true
		trigger = _touching(pos, half, triggers)
		if trigger >= 0:
			break
		if bounds.has_area() and not bounds.has_point(pos):
			break
		if grounded:
			launched = false
			cut = false
			if frame > 2 and airborne:
				landed = true
				floor = resolved["floor"]
				break
	return {
		"position": pos,
		"velocity": vel,
		"landed": landed,
		"floor": floor,
		"min_feet": min_feet,
		"trigger": trigger,
	}


static func _touching(center: Vector2, half: Vector2, triggers: Array) -> int:
	for i in triggers.size():
		if _overlaps(center, half, triggers[i]):
			return i
	return -1


static func _overlaps(center: Vector2, half: Vector2, block: Rect2) -> bool:
	var left := center.x - half.x
	var top := center.y - half.y
	var right := center.x + half.x
	var bottom := center.y + half.y
	return not (right <= block.position.x or left >= block.end.x or bottom <= block.position.y or top >= block.end.y)
