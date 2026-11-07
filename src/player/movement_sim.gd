class_name MovementSim
extends RefCounted

## All of the player's movement. The player and the reach solver both advance
## a State with step(), so a jump the solver finds is a jump the player makes.
## Anything that asks whether a jump works (the solver, the legacy Imprint preview) calls simulate_jump() against a room's
## rectangles instead of copying these formulas.
##
## Moving platforms come in as `movers` and the tick they are at. A body
## standing on one is carried by it, one that it runs into is pushed, and one
## pushed into a wall is crushed. Leaving a platform keeps only the body's own
## velocity, unless the config says to add the platform's.

const HALF := Vector2(Grid.CELL * 0.5, Grid.CELL * 0.5)
## An empty list of rects, for a body with no moving platforms to test. Never
## added to.
const NO_RECTS: Array = []

## Tongue Climb. A body is not climbing, being pulled to its wall, or hanging
## there. `Player` and `TongueLash` start it (`start_climb`); `step` runs it.
const CLIMB_NONE := 0
const CLIMB_ZIP := 1
const CLIMB_HOLD := 2
## The gap, in pixels, between the front of a hanging body and the wall, so the
## tongue shows between them. A body that was already closer stays where it is.
const CLIMB_GAP := 4.0
## How far (px) the tongue's tip may be from the wall face it stuck to. The tip
## stops within one step (4 px) of the face, and its box is 3 px deep.
const CLIMB_TIP_BEFORE := 2.5
const CLIMB_TIP_PAST := 1.5
## The pull's path is checked in steps of this many pixels (`TongueReach.STEP`).
const CLIMB_STEP := 4.0
## What a tick of climbing tells `step` to do next with the rest of the tick.
const _CLIMB_DONE := 0
const _CLIMB_FALL := 1
const _CLIMB_WALL_JUMP := 2
const _CLIMB_CEILING_DROP := 3


## What a body carries from one tick to the next.
class State extends RefCounted:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var grounded := false
	var coyote := 0.0
	var buffer := 0.0
	var launched := false
	var cut := false
	## Air jumps the body may make before it next lands (the owner sets it from
	## the abilities), and how many it has left. Landing refills `air_left`.
	var air_jumps := 0
	var air_left := 0
	## Set by step(): a jump began this tick, and the rect the body is
	## standing on, if any.
	var jumped := false
	## Set by step(): that jump was an air jump.
	var air_jumped := false
	var floor_rect := Rect2()
	## The moving platform the body is standing on, or -1.
	var riding := -1
	## Set by step(): a moving platform pushed the body into something solid, or
	## it touched a spiked body of a mover. Either way it dies, like spikes.
	var crushed := false
	## Tongue Climb: CLIMB_NONE, CLIMB_ZIP (being pulled) or CLIMB_HOLD (hanging).
	var climb := 0
	## The unit direction of the wall from the body: (+-1, 0), or (0, -1) for a ceiling.
	var climb_dir := Vector2.ZERO
	## Where the body's centre hangs, and how fast it is pulled there (px/s).
	var climb_anchor := Vector2.ZERO
	var zip_speed := 0.0
	## Seconds of the hang left.
	var climb_left := 0.0
	## Seconds the hang lasts in all, set when the climb starts.
	var climb_hold := 0.0
	## The tongue found something in the way: the body is pulled as far as it
	## can go, and lets go on arriving.
	var climb_abort := false
	## After a hang that ran out, whether the body must land before it may stick again.
	var climb_relock := false
	var climb_locked := false
	## Set by step(): the body let go of the wall or ceiling this tick.
	var released := false
	## Set by step(): it let go this tick because of a jump press (a wall jump,
	## or a drop from a ceiling), as against the hang running out or being cut.
	var left_by_jump := false
	## A ground jump held in hand after dropping from a ceiling: the next press,
	## wherever in the fall, is a full jump, and the one after is the air jump.
	## Landing, or starting a climb, takes it away.
	var spare_jump := false
	## Set by step(): the area the body passed through while it was pulled to its
	## wall this tick (its box at the start joined to its box at the end), so a
	## fast pull cannot skip over spikes. Empty on any other tick.
	var climb_swept := Rect2()


## One physics tick: read input, apply forces, round corners, collide.
## `movers` are the room's moving platforms, which go from where they are at
## `tick` to where they are at `tick + 1` during this step.
static func step(
	cfg: MovementConfig,
	s: State,
	rects: Array,
	input_x: float,
	jump_pressed: bool,
	jump_held: bool,
	delta: float,
	movers: Movers = null,
	tick := 0
) -> void:
	var was_riding := s.riding
	s.released = false
	s.left_by_jump = false
	s.climb_swept = Rect2()
	if s.climb != CLIMB_NONE:
		match _climb_tick(cfg, s, rects, jump_pressed, delta, movers, tick):
			_CLIMB_DONE:
				return
			_CLIMB_WALL_JUMP:
				jump_pressed = true
			_CLIMB_CEILING_DROP:
				jump_pressed = false
	# The platforms, where they will be after this tick, are tested after the
	# room's own solids, as if appended to them.
	var extra: Array = NO_RECTS
	s.crushed = false
	if movers != null and not movers.is_empty():
		move_with(s, rects, movers, tick)
		extra = movers.rects(tick + 1)
	_integrate(cfg, s, input_x, jump_pressed, jump_held, delta)
	s.position = corner_correct(cfg, s.position, s.velocity, s.grounded, rects, delta, extra)
	_resolve(s, rects, extra, delta)
	s.riding = -1
	if s.grounded:
		s.launched = false
		s.cut = false
		s.climb_locked = false
		s.spare_jump = false
		s.air_left = s.air_jumps
		if movers != null:
			for i in movers.size():
				if not movers.hazard(i) and movers.alive(i, tick + 1) and s.floor_rect == movers.rect(i, tick + 1):
					s.riding = i
					break
	if movers != null and not movers.is_empty() and _touches_hazard_body(s.position, movers, tick + 1):
		s.crushed = true
	# Off a platform and into the air: the body keeps only its own velocity,
	# unless the platform's is to be added.
	if was_riding >= 0 and not s.grounded and cfg.inherit_platform_velocity:
		s.velocity += movers.step_of(was_riding, tick) / delta


## Starts a climb for a body whose tongue stuck at `tip` in direction `dir` (a
## wall to the side, or the ceiling above): the body is pulled along the tongue
## and then hangs for `hold` seconds. The hanging place is worked out here: the
## body is slid toward the wall until a solid stops it (as `resolve` does), and
## hangs `CLIMB_GAP` short of that, so the tongue shows. If the solid that stops
## it is not the tongue's wall (a ledge under its feet, say), it is pulled as
## far as it can go and then lets go (`climb_abort`). Returns false and changes
## nothing if the body is already climbing or must land first.
static func start_climb(s: State, rects: Array, tip: Vector2, dir: Vector2, hold: float, zip_speed: float, relock: bool) -> bool:
	if s.climb != CLIMB_NONE or s.climb_locked:
		return false
	var remaining := (tip - (s.position + dir * HALF.x)).dot(dir)
	var asked := maxf(remaining + CLIMB_TIP_PAST + 1.5, 0.0)
	# Slid in steps no longer than the tongue's, so a thin ledge cannot be skipped.
	var flush := s.position
	var left := asked
	var stopped := false
	while left > 0.0:
		var step := minf(left, CLIMB_STEP)
		var next := _shift(flush, dir * step, rects)
		var moved := (next - flush).dot(dir)
		flush = next
		left -= step
		if moved < step - 0.001:
			stopped = true
			break
	var travelled := (flush - s.position).dot(dir)
	s.climb_abort = not stopped or travelled < remaining - CLIMB_TIP_BEFORE
	var anchor := flush if s.climb_abort else flush - dir * CLIMB_GAP
	if (anchor - s.position).dot(dir) < 0.0:
		anchor = s.position
	s.climb = CLIMB_ZIP
	s.spare_jump = false
	s.climb_dir = dir
	s.climb_anchor = anchor
	s.zip_speed = zip_speed
	s.climb_hold = hold
	s.climb_left = hold
	s.climb_relock = relock
	s.grounded = false
	s.floor_rect = Rect2()
	s.riding = -1
	s.velocity = Vector2.ZERO
	return true


## Lets go: the body keeps no speed, and falls from this tick on.
static func release_climb(s: State) -> void:
	if s.climb == CLIMB_NONE:
		return
	s.climb = CLIMB_NONE
	s.climb_abort = false
	s.velocity = Vector2.ZERO
	s.released = true


## Lets go because the hang is over, not because of a jump, and keeps both
## jumps for the player. Off a wall the body gets a ledge's coyote time, so a
## press as it lets go (the end of the wiggle) is a full jump off the wall and
## the air jump is kept. From a ceiling there is no jumping straight away, so it
## gets a spare ground jump to use at any point in the fall, and the air jump
## is ready too.
static func drop_climb(cfg: MovementConfig, s: State) -> void:
	if s.climb == CLIMB_NONE:
		return
	var wall := s.climb_dir.y == 0.0
	var hung := s.climb == CLIMB_HOLD
	release_climb(s)
	if not hung:
		# Let go on the way there: he never stuck, so nothing is given back.
		return
	if wall:
		s.coyote = cfg.coyote_time
	else:
		s.spare_jump = true
		s.air_left = s.air_jumps


## Whether the body is hanging with the wiggle due: the last `wiggle` seconds of the hang.
static func wiggling(s: State, wiggle: float) -> bool:
	return s.climb == CLIMB_HOLD and wiggle > 0.0 and s.climb_left <= wiggle + 0.0001


## One tick of a body that is being pulled to its wall or hanging on it. Returns
## what `step` does with the rest of the tick: nothing (the body stayed on the
## wall), or fall through to the ordinary movement as it is, as a ground jump
## from the wall, or without a jump press (a drop from the ceiling).
static func _climb_tick(cfg: MovementConfig, s: State, rects: Array, jump_pressed: bool, delta: float, movers: Movers, tick: int) -> int:
	s.crushed = false
	s.jumped = false
	s.air_jumped = false
	s.grounded = false
	s.floor_rect = Rect2()
	s.riding = -1
	s.velocity = Vector2.ZERO
	if jump_pressed:
		s.buffer = cfg.jump_buffer
	else:
		s.buffer = maxf(0.0, s.buffer - delta)
	if movers != null and not movers.is_empty():
		var before := s.position
		move_with(s, rects, movers, tick)
		if s.crushed or s.position != before:
			# A platform pushed the body off the wall.
			drop_climb(cfg, s)
			return _CLIMB_FALL
	var holding := s.climb == CLIMB_HOLD
	if s.climb == CLIMB_ZIP:
		var to := s.climb_anchor - s.position
		var dist := to.length()
		var reach := minf(s.zip_speed * delta, dist)
		var start := s.position
		var cleared := true
		if reach > 0.0:
			# Pulled in steps no longer than the tongue's, against the room and
			# the moving platforms as they will be, so neither can be skipped.
			var solid: Array = rects
			if movers != null and not movers.is_empty():
				solid = rects + movers.rects(tick + 1)
			var along := to / dist
			var done := 0.0
			while done < reach - 0.0001:
				var piece := minf(reach - done, CLIMB_STEP)
				var next := _shift(s.position, along * piece, solid)
				var moved := (next - s.position).length()
				s.position = next
				done += piece
				if movers != null and not movers.is_empty() and _touches_hazard_body(s.position, movers, tick + 1):
					s.crushed = true
					cleared = false
					break
				if moved < piece - 0.001:
					cleared = false
					break
		s.climb_swept = Rect2(start - HALF, HALF * 2.0).merge(Rect2(s.position - HALF, HALF * 2.0))
		if not cleared:
			# Something is in the way of the pull: he stops there and lets go.
			release_climb(s)
			return _CLIMB_DONE if s.crushed else _CLIMB_FALL
		if reach >= dist - 0.0001:
			s.position = s.climb_anchor
			if s.climb_abort:
				release_climb(s)
				return _CLIMB_FALL
			s.climb = CLIMB_HOLD
			s.climb_left = s.climb_hold
			s.air_left = s.air_jumps
	if s.climb == CLIMB_HOLD:
		if s.buffer > 0.0:
			var wall := s.climb_dir.y == 0.0
			release_climb(s)
			s.left_by_jump = true
			if wall:
				s.coyote = cfg.coyote_time
				return _CLIMB_WALL_JUMP
			s.coyote = 0.0
			s.buffer = 0.0
			s.air_left = s.air_jumps
			s.spare_jump = true
			return _CLIMB_CEILING_DROP
		if holding:
			s.climb_left -= delta
		if s.climb_left <= 0.0001:
			s.climb_locked = s.climb_relock
			drop_climb(cfg, s)
			return _CLIMB_FALL
	if movers != null and not movers.is_empty() and _touches_hazard_body(s.position, movers, tick + 1):
		s.crushed = true
	return _CLIMB_DONE


## The moving platforms' share of a tick, before the body's own: the one it
## stands on carries it, and any other that moves into it pushes it out the
## way that platform is going. Walls stop both. A body still inside a platform
## or a wall afterwards is crushed.
static func move_with(s: State, rects: Array, movers: Movers, tick: int) -> void:
	var start := s.position
	if s.riding >= 0 and s.riding < movers.size():
		s.position = _shift(s.position, movers.step_of(s.riding, tick), rects)
	for i in movers.size():
		if i == s.riding or movers.hazard(i) or not movers.alive(i, tick + 1):
			continue
		var after := movers.rect(i, tick + 1)
		if not _overlaps(s.position, HALF, after):
			continue
		var push := _push_out(s.position, after, movers.step_of(i, tick))
		s.position = _shift(s.position, push, rects)
		if _overlaps(s.position, HALF, after):
			s.crushed = true
	if s.position != start and _blocked(s.position, HALF, rects, Vector2.ZERO):
		s.crushed = true


## Whether a body at `position` overlaps a spiked mover body at `tick`.
static func _touches_hazard_body(position: Vector2, movers: Movers, tick: int) -> bool:
	for rect in movers.hazard_rects(tick):
		if _overlaps(position, HALF, rect):
			return true
	return false


## Moves a body by `motion`, stopping it at walls.
static func _shift(position: Vector2, motion: Vector2, rects: Array) -> Vector2:
	if motion == Vector2.ZERO:
		return position
	return resolve(position, motion, rects, 1.0, HALF)["position"]


## How far a body at `position` has to move to leave `block`, which is moving
## by `motion`: out of its leading side.
static func _push_out(position: Vector2, block: Rect2, motion: Vector2) -> Vector2:
	if absf(motion.x) >= absf(motion.y):
		if motion.x > 0.0:
			return Vector2(block.end.x + HALF.x - position.x, 0.0)
		if motion.x < 0.0:
			return Vector2(block.position.x - HALF.x - position.x, 0.0)
		return Vector2.ZERO
	if motion.y > 0.0:
		return Vector2(0.0, block.end.y + HALF.y - position.y)
	return Vector2(0.0, block.position.y - HALF.y - position.y)


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
	delta: float,
	extra: Array = NO_RECTS
) -> Vector2:
	var max_px := int(round(cfg.corner_correction))
	if max_px <= 0:
		return position
	var pos := position
	if not grounded and absf(velocity.x) > 1.0 and velocity.y >= 0.0:
		var horiz := Vector2(velocity.x * delta, 0.0)
		if _blocked(pos, HALF, rects, horiz, extra):
			for n in max_px:
				var lift := float(n + 1)
				if not _blocked(pos + Vector2(0.0, -lift), HALF, rects, horiz, extra):
					pos.y -= lift
					break
	if velocity.y < 0.0:
		var vert := Vector2(0.0, velocity.y * delta)
		if _blocked(pos, HALF, rects, vert, extra):
			var prefer := signf(velocity.x) if absf(velocity.x) > 1.0 else 1.0
			var pushed := false
			for dir in [prefer, -prefer]:
				if pushed:
					break
				var direction := float(dir)
				for n in max_px:
					var push := float(n + 1) * direction
					if not _blocked(pos + Vector2(push, 0.0), HALF, rects, vert, extra):
						pos.x += push
						pushed = true
						break
	return pos


## Input, gravity and the jump rules for one tick, on the body's velocity and
## timers in `s` (not its position).
static func _integrate(cfg: MovementConfig, s: State, input_x: float, jump_pressed: bool, jump_held: bool, delta: float) -> void:
	var velocity := s.velocity
	var grounded := s.grounded
	var coyote := s.coyote
	var buffer := s.buffer
	var launched := s.launched
	var cut := s.cut
	var air_jumps := s.air_jumps
	var air_left := s.air_left
	var spare := s.spare_jump
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
	var air_jumped := false
	if grounded:
		air_left = air_jumps
	else:
		air_left = mini(air_left, air_jumps)
	if buffer > 0.0 and coyote > 0.0:
		velocity.y = -cfg.jump_speed
		jumped = true
		launched = true
		cut = false
		coyote = 0.0
		buffer = 0.0
	elif jump_pressed and spare:
		# The ground jump a ceiling drop left in hand: as strong as a ground
		# jump, and the air jump is still to come.
		velocity.y = -cfg.jump_speed
		jumped = true
		launched = true
		cut = false
		spare = false
		buffer = 0.0
	elif jump_pressed and air_left > 0:
		# A fresh press in the air, with no ground or coyote jump to use: a
		# second jump, as strong as the first, from whatever speed it was at.
		velocity.y = -cfg.air_jump_speed
		jumped = true
		air_jumped = true
		launched = true
		cut = false
		air_left -= 1
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

	s.velocity = velocity
	s.coyote = coyote
	s.buffer = buffer
	s.launched = launched
	s.cut = cut
	s.jumped = jumped
	s.air_jumped = air_jumped
	s.air_left = air_left
	s.spare_jump = spare


## Moves the body in `s` by its velocity for `delta`, along x and then y, and
## stops it at the first of `rects` and then `extra` it would overlap: the
## last overlapping block on each axis decides. Sets its position, velocity,
## `grounded` and `floor_rect`.
static func _resolve(s: State, rects: Array, extra: Array, delta: float) -> void:
	var pos := s.position
	var vel := s.velocity
	pos.x += vel.x * delta
	for rect in rects:
		var block: Rect2 = rect
		if _overlaps(pos, HALF, block):
			pos.x = _stop_x(pos.x, vel.x, block)
			vel.x = 0.0
	for rect in extra:
		var block: Rect2 = rect
		if _overlaps(pos, HALF, block):
			pos.x = _stop_x(pos.x, vel.x, block)
			vel.x = 0.0
	pos.y += vel.y * delta
	s.grounded = false
	s.floor_rect = Rect2()
	for rect in rects:
		var block: Rect2 = rect
		if _overlaps(pos, HALF, block):
			if vel.y >= 0.0:
				s.grounded = true
				s.floor_rect = block
			pos.y = _stop_y(vel.y, block)
			vel.y = 0.0
	for rect in extra:
		var block: Rect2 = rect
		if _overlaps(pos, HALF, block):
			if vel.y >= 0.0:
				s.grounded = true
				s.floor_rect = block
			pos.y = _stop_y(vel.y, block)
			vel.y = 0.0
	s.position = pos
	s.velocity = vel


## Where a body moving at `vx` that overlaps `block` stops along x.
static func _stop_x(x: float, vx: float, block: Rect2) -> float:
	if vx > 0.0:
		return block.position.x - HALF.x
	if vx < 0.0:
		return block.end.x + HALF.x
	return x


## Where a body moving at `vy` that overlaps `block` stops along y: on top of
## it when falling or still, under it when rising.
static func _stop_y(vy: float, block: Rect2) -> float:
	if vy >= 0.0:
		return block.position.y - HALF.y
	return block.end.y + HALF.y


## `_resolve` for a body of half-size HALF that is not in a State, as
## {"position", "velocity", "grounded", "floor"}.
static func resolve(position: Vector2, velocity: Vector2, rects: Array, delta: float, half: Vector2 = HALF) -> Dictionary:
	assert(half == HALF, "MovementSim moves bodies of half-size HALF only")
	var s := State.new()
	s.position = position
	s.velocity = velocity
	_resolve(s, rects, NO_RECTS, delta)
	return {
		"position": s.position,
		"velocity": s.velocity,
		"grounded": s.grounded,
		"floor": s.floor_rect,
	}


## Runs one input plan from a standing start until the body lands, touches a
## trigger, or leaves `bounds`. `jump` false walks (or drops) without jumping.
## `triggers` are pixel rects; the result's "trigger" is the index of the first
## one touched, or -1. A path that touches a `hazards` rect ends there and
## reports "hazard": true, since the body would have died. An empty `bounds`
## means no limit. `movers` are the room's moving platforms, at `start_tick` on
## the first frame. `start_riding` is the one the body starts standing on, or
## -1. The result's "riding" is the one it landed on, or -1, and a body that
## is crushed counts as a hazard. "bounds" is the box the body's centre stayed
## in, from the start to where it stopped: grown by the body and what a tick
## can move or probe (see ReachGraph.reuse_margin), it is everything the path
## could have touched.
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
	record: bool = false,
	movers: Movers = null,
	start_tick := 0,
	start_riding := -1,
	air_jumps := 0,
	air_frame := -1,
	air_hold := 0
) -> Dictionary:
	var plan := JumpPlan.new(rects, start_position, start_velocity, input_x, hold_frames)
	plan.grounded_start = grounded_start
	plan.jump = jump
	plan.triggers = triggers
	plan.bounds = bounds
	plan.hazards = hazards
	plan.collect = collect
	plan.later_input = later_input
	plan.switch_frame = switch_frame
	plan.limit = limit
	plan.record = record
	plan.movers = movers
	plan.start_tick = start_tick
	plan.start_riding = start_riding
	plan.air_jumps = air_jumps
	plan.air_frame = air_frame
	plan.air_hold = air_hold
	return run(cfg, plan)


## `simulate_jump` with the plan's settings named (see JumpPlan).
static func run(cfg: MovementConfig, plan: JumpPlan) -> Dictionary:
	var s := State.new()
	s.air_jumps = plan.air_jumps
	s.air_left = plan.air_jumps
	s.position = plan.start_position
	s.velocity = plan.start_velocity
	s.grounded = plan.grounded_start
	s.riding = plan.start_riding
	s.coyote = cfg.coyote_time if plan.grounded_start else 0.0
	if plan.hang_dir != Vector2.ZERO:
		s.climb = CLIMB_HOLD
		s.climb_dir = plan.hang_dir
		s.climb_anchor = s.position
		s.climb_hold = plan.hang_time
		s.climb_left = plan.hang_time
		s.grounded = false
		s.coyote = 0.0
	var delta := 1.0 / 60.0
	var min_feet := s.position.y + HALF.y
	var low := s.position
	var high := s.position
	var landed := false
	var airborne := false
	var trigger := -1
	var hazard := false
	var floor_rect := Rect2()
	var collected: Array[int] = []
	var path := PackedVector2Array()
	if plan.record:
		path.append(plan.start_position)
	var has_bounds := plan.bounds.has_area()
	var switching := not is_nan(plan.later_input)
	var air_frame := plan.air_frame
	var frames := 0
	for frame in plan.limit:
		frames = frame + 1
		var input := plan.input_x if not switching or frame < plan.switch_frame else plan.later_input
		# A second press at `air_frame`, held for `air_hold` ticks, replaces the first jump's hold.
		var press := (plan.jump and frame == 0) or frame == air_frame
		var held := frame < plan.hold_frames if air_frame < 0 or frame < air_frame else frame < air_frame + plan.air_hold
		step(cfg, s, plan.rects, input, press, held, delta, plan.movers, plan.start_tick + frame)
		if plan.record:
			path.append(s.position)
		min_feet = minf(min_feet, s.position.y + HALF.y)
		low = low.min(s.position)
		high = high.max(s.position)
		if not s.grounded:
			airborne = true
		if s.crushed or _touching(s.position, HALF, plan.hazards) >= 0:
			hazard = true
			break
		for i in plan.collect.size():
			if not collected.has(i) and _overlaps(s.position, HALF, plan.collect[i]):
				collected.append(i)
		trigger = _touching(s.position, HALF, plan.triggers)
		if trigger >= 0:
			break
		if has_bounds and not plan.bounds.has_point(s.position):
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
		"riding": s.riding if landed else -1,
		"tick": plan.start_tick + frames,
		"bounds": Rect2(low, high - low),
	}


static func _touching(center: Vector2, half: Vector2, triggers: Array) -> int:
	for i in triggers.size():
		if _overlaps(center, half, triggers[i]):
			return i
	return -1


## Whether the body, moved by `motion`, would overlap a block.
static func _blocked(center: Vector2, half: Vector2, rects: Array, motion: Vector2, extra: Array = NO_RECTS) -> bool:
	var moved := center + motion
	for rect in rects:
		if _overlaps(moved, half, rect):
			return true
	for rect in extra:
		if _overlaps(moved, half, rect):
			return true
	return false


static func _overlaps(center: Vector2, half: Vector2, block: Rect2) -> bool:
	var left := center.x - half.x
	var top := center.y - half.y
	var right := center.x + half.x
	var bottom := center.y + half.y
	return not (right <= block.position.x or left >= block.end.x or bottom <= block.position.y or top >= block.end.y)
