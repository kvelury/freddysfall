class_name MovementSim
extends RefCounted

## All of the player's movement. The player and the reach solver both advance
## a State with step(), so a jump the solver finds is a jump the player makes.
## Imprint reachability should call simulate_jump() against a room's
## rectangles instead of copying these formulas.

const HALF := Vector2(Grid.CELL * 0.5, Grid.CELL * 0.5)


## What a body carries from one tick to the next.
class State extends RefCounted:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var grounded := false
	var coyote := 0.0
	var buffer := 0.0
	var launched := false
	var cut := false
	## Set by step(): a jump began this tick, and the rect the body is
	## standing on, if any.
	var jumped := false
	var floor_rect := Rect2()
	var scratch := {}


## One physics tick: read input, apply forces, round corners, collide.
static func step(
	cfg: MovementConfig,
	s: State,
	rects: Array,
	input_x: float,
	jump_pressed: bool,
	jump_held: bool,
	delta: float
) -> void:
	integrate(
		cfg, s.velocity, s.grounded, s.coyote, s.buffer, s.launched, s.cut,
		input_x, jump_pressed, jump_held, delta, s.scratch
	)
	s.velocity = s.scratch["velocity"]
	s.coyote = s.scratch["coyote"]
	s.buffer = s.scratch["buffer"]
	s.launched = s.scratch["launched"]
	s.cut = s.scratch["cut"]
	s.jumped = s.scratch["jumped"]
	s.position = corner_correct(cfg, s.position, s.velocity, s.grounded, rects, delta)
	var resolved := resolve(s.position, s.velocity, rects, delta, HALF)
	s.position = resolved["position"]
	s.velocity = resolved["velocity"]
	s.grounded = resolved["grounded"]
	s.floor_rect = resolved["floor"]
	if s.grounded:
		s.launched = false
		s.cut = false


## Whether a body at `position` is resting on something: a probe one pixel down.
static func standing(position: Vector2, rects: Array) -> bool:
	return _blocked(position, HALF, rects, Vector2(0.0, 1.0))


## Ledge and ceiling forgiveness. A body that clips a ledge by a few pixels
## is lifted onto it, and one that clips a ceiling corner by a few pixels while
## rising is pushed to the side. Both look ahead with a test, and never move
## the body through a block. Returns the corrected position.
static func corner_correct(
	cfg: MovementConfig,
	position: Vector2,
	velocity: Vector2,
	grounded: bool,
	rects: Array,
	delta: float
) -> Vector2:
	var max_px := int(round(cfg.corner_correction))
	if max_px <= 0:
		return position
	var pos := position
	if not grounded and absf(velocity.x) > 1.0 and velocity.y >= 0.0:
		var horiz := Vector2(velocity.x * delta, 0.0)
		if _blocked(pos, HALF, rects, horiz):
			for n in max_px:
				var lift := float(n + 1)
				if not _blocked(pos + Vector2(0.0, -lift), HALF, rects, horiz):
					pos.y -= lift
					break
	if velocity.y < 0.0:
		var vert := Vector2(0.0, velocity.y * delta)
		if _blocked(pos, HALF, rects, vert):
			var prefer := signf(velocity.x) if absf(velocity.x) > 1.0 else 1.0
			var pushed := false
			for dir in [prefer, -prefer]:
				if pushed:
					break
				var direction := float(dir)
				for n in max_px:
					var push := float(n + 1) * direction
					if not _blocked(pos + Vector2(push, 0.0), HALF, rects, vert):
						pos.x += push
						pushed = true
						break
	return pos


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
## one touched, or -1. A path that touches a `hazards` rect ends there and
## reports "hazard": true, since the body would have died. An empty `bounds`
## means no limit.
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
	bounds: Rect2 = Rect2(),
	hazards: Array = [],
	collect: Array = [],
	later_input: float = NAN,
	switch_frame: int = 0,
	limit: int = 180,
	record: bool = false
) -> Dictionary:
	var s := State.new()
	s.position = start_position
	s.velocity = start_velocity
	s.grounded = grounded_start
	s.coyote = cfg.coyote_time if grounded_start else 0.0
	var delta := 1.0 / 60.0
	var min_feet := s.position.y + HALF.y
	var landed := false
	var airborne := false
	var trigger := -1
	var hazard := false
	var floor_rect := Rect2()
	var collected: Array[int] = []
	var path := PackedVector2Array()
	if record:
		path.append(start_position)
	var frames := 0
	for frame in limit:
		frames = frame + 1
		var input := input_x if is_nan(later_input) or frame < switch_frame else later_input
		step(cfg, s, rects, input, jump and frame == 0, frame < hold_frames, delta)
		if record:
			path.append(s.position)
		min_feet = minf(min_feet, s.position.y + HALF.y)
		if not s.grounded:
			airborne = true
		if _touching(s.position, HALF, hazards) >= 0:
			hazard = true
			break
		for i in collect.size():
			if not collected.has(i) and _overlaps(s.position, HALF, collect[i]):
				collected.append(i)
		trigger = _touching(s.position, HALF, triggers)
		if trigger >= 0:
			break
		if bounds.has_area() and not bounds.has_point(s.position):
			break
		if s.grounded and frame > 2 and airborne:
			landed = true
			floor_rect = s.floor_rect
			break
	return {
		"position": s.position,
		"velocity": s.velocity,
		"landed": landed,
		"floor": floor_rect,
		"min_feet": min_feet,
		"trigger": trigger,
		"hazard": hazard,
		"collected": collected,
		"frames": frames,
		"path": path,
	}


static func _touching(center: Vector2, half: Vector2, triggers: Array) -> int:
	for i in triggers.size():
		if _overlaps(center, half, triggers[i]):
			return i
	return -1


## Whether the body, moved by `motion`, would overlap a block.
static func _blocked(center: Vector2, half: Vector2, rects: Array, motion: Vector2) -> bool:
	var moved := center + motion
	for rect in rects:
		if _overlaps(moved, half, rect):
			return true
	return false


static func _overlaps(center: Vector2, half: Vector2, block: Rect2) -> bool:
	var left := center.x - half.x
	var top := center.y - half.y
	var right := center.x + half.x
	var bottom := center.y + half.y
	return not (right <= block.position.x or left >= block.end.x or bottom <= block.position.y or top >= block.end.y)
