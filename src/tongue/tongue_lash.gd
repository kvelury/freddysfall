class_name TongueLash
extends Node2D

## Tongue Lash. Once it is found, `lash` sends Freddy's tongue out of the notch
## in the front of his body, the way he faces, and pulls it back in. The tip
## goes out until it meets something solid or runs out of length
## (`Abilities.tongue_length`), and then the tongue snaps back. How it moves, out
## and in, is `TongueMotion`'s: a creep, a snap, a stick on what it hit and a
## return that averages `Abilities.tongue_snap` times `tongue_speed`.
## What the tip meets is dealt with as the gun's shot was: a breakable wall takes a hit
## (see BreakableWall), anything else stops it. One lash hits at most one thing.
## There is no aiming, so a player who wants to reach higher jumps first. With
## `look_up` (Up or W) held when `lash` (B) is pressed, the tongue goes straight
## up out of the top of his head instead, for a wall or platform above him.
##
## Two keys pressed "together" land a frame or two apart, and a press often
## comes a little before the lash can be made, so the input is lenient. A press
## that comes while the tongue is out, coming back, cooling down or hanging is
## kept for `LASH_BUFFER` seconds and made as soon as it may (one press is kept,
## not a queue). A sideways lash turns to go up if `look_up` is pressed within
## `UP_GRACE` seconds of it, while the tip is still going out and has hit
## nothing.
##
## With Tongue Climb (`Abilities.tongue_climb`) a tip that sticks to a plain wall
## (or a breakable one that is still standing, or, going up, the ceiling) pulls
## Freddy to it instead of coming back: the CLIMB phase. He hangs by the tongue
## until the player's body lets go (a jump, the time running out, the wall
## going), and the tongue then goes back in. The pull and the hang are
## `MovementSim`'s, so the solver can use them later.
##
## It is a child of the world and uses its `current` room, `player` and
## `imprint`. A lash belongs to the room it was made in: leaving, dying and
## warping clear it. Turning round, or the world going busy, cuts it short.

## The tip moves in steps no longer than this, so a fast one cannot skip a cell.
const STEP := TongueReach.STEP
## Half the body's width, in pixels: the tongue's length is counted from the
## front of the body.
const FRONT := TongueReach.FRONT
## The mouth's height above the body's centre, in pixels. The hit is made here
## whatever picture is on show; only the drawing follows the picture.
const MOUTH_RISE := TongueReach.MOUTH_RISE
## The size of the tip's box, in pixels.
const TIP := TongueReach.TIP
## The tip's box going up, in pixels.
const TIP_UP := TongueReach.TIP_UP
const PINK := Color("ff6fa8")
## How long a press that came too early is kept, in seconds: the jump buffer's.
const LASH_BUFFER := 0.12
## How long after a sideways lash pressing `look_up` still sends it up, in
## seconds (3 ticks).
const UP_GRACE := 0.05

## The parts of a lash. OUT is the creep and the snap; STICK holds the tip on
## what it hit; BACK is the return; CLIMB holds the tip while Freddy hangs from it.
enum Phase { OUT, STICK, BACK, CLIMB }

## The headless tests set `scripted` and lash with `scripted_lash`.
var scripted := false
var scripted_lash := false
## The tests' stand-in for holding the look-up key when a lash is made.
var scripted_up := false

## Whether a tongue is out, going or coming back.
var active := false
## 1 right, -1 left: the way the tongue was sent.
var direction := 1
## Whether the tongue was sent straight up.
var up := false
## Pixels from the front of the body to the tip.
var extension := 0.0
## Which part of the lash the tongue is in.
var phase := Phase.OUT
## Whether the tongue has turned for home: stuck or coming back.
var retracting: bool:
	get:
		return active and phase != Phase.OUT
## Seconds spent in the current phase.
var _time := 0.0
## The return: the pixels out when it began, and the seconds it takes.
var _back_from := 0.0
var _back_duration := 0.0
## Whether the tip's last hit was on something (a wall or a solid), as against
## running out of length or leaving the room. Only that sticks.
var _struck := false
## Whether what the tip struck is something Freddy can hang from: a plain
## solid or door block, or a breakable wall still standing after the hit.
var _climbable := false
## Whether the strike was on a breakable wall, and whether the hang is on one.
var _struck_wall := false
var _stuck_breakable := false
## Where the tip stuck, for a climb, in world pixels.
var _stuck_tip := Vector2.ZERO
## Where the tip stuck, as a world coordinate along the tongue: x going sideways,
## y going up.
var _stuck_at := 0.0
## Seconds before another lash may be made. It runs only while the tongue is in.
var cooldown_left := 0.0
## A press kept because it came too early: seconds it is still good for, and
## whether look-up was held with it.
var buffer_left := 0.0
var _buffer_up := false
## Seconds since this lash was sent, for the up grace.
var _sent_for := 0.0

var _world: Node
var _player: Player


func _ready() -> void:
	# Drawn from _process, in whole pixels.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world = get_parent()
	_player = _world.get_node("Player")
	GameState.abilities_changed.connect(_reconcile_abilities)


## Whether a press sends the tongue out now: Tongue Lash has been found, none is
## out, the last has been back long enough, and the player is in control in a room.
func can_lash() -> bool:
	return _lash_allowed() and _tongue_ready()


## Whether the player may lash at all just now: the power is found and the
## player is in control in a room. A press made when this is false is dropped.
func _lash_allowed() -> bool:
	return GameState.abilities.tongue_unlocked and not _world.gameplay_input_blocked() and _player.input_enabled and _world.current != null and not _world.is_busy()


## Whether the tongue is free: none is out, the last has been back long enough
## and Freddy is not hanging. A press made when this is false is kept a while.
func _tongue_ready() -> bool:
	return not active and not _player.climbing() and cooldown_left <= 0.0


## Lashes if it may. Returns whether it did.
func lash(upward := false) -> bool:
	if not can_lash():
		return false
	active = true
	direction = _player.facing
	_send(upward)
	return true


## Sends the tongue out from the mouth, sideways or up.
func _send(upward: bool) -> void:
	up = upward
	_player.lashing_up = upward
	extension = 0.0
	_sent_for = 0.0
	_reset_phase()
	# A lash against a wall the player is pressed to hits it at once.
	if _hit():
		_begin_return()
	queue_redraw()


## Pulls the tongue in at once and starts the wait for the next lash.
func end() -> void:
	if active:
		cooldown_left = GameState.abilities.tongue_cooldown
	if _player != null:
		_player.end_climb()
	active = false
	up = false
	_player.lashing_up = false
	extension = 0.0
	_reset_phase()
	queue_redraw()


## Forgets a press that was being kept.
func drop_buffer() -> void:
	buffer_left = 0.0
	_buffer_up = false


## Removes the tongue, the wait for the next lash and any kept press.
func clear() -> void:
	drop_buffer()
	active = false
	up = false
	if _player != null:
		_player.end_climb()
		_player.lashing_up = false
	extension = 0.0
	_reset_phase()
	cooldown_left = 0.0
	queue_redraw()


## The world position of the tip.
func tip() -> Vector2:
	if up:
		return _player.global_position + Vector2(0.0, -(FRONT + extension))
	return _player.global_position + Vector2(float(direction) * (FRONT + extension), -MOUTH_RISE)


func _physics_process(delta: float) -> void:
	if _world.current == null or _world.is_busy():
		end()
		drop_buffer()
		return
	var pressed := scripted_lash if scripted else Input.is_action_just_pressed("lash")
	var upward := scripted_up if scripted else Input.is_action_pressed("look_up")
	scripted_lash = false
	if active and not up and _player.facing != direction:
		end()
	if active and not up and phase == Phase.OUT and _sent_for < UP_GRACE - 0.001 and upward and _lash_allowed():
		# Look-up came a moment after the lash: it goes up after all.
		_send(true)
	if not active:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
	else:
		_move(delta)
		_sent_for += delta
	if not _lash_allowed():
		drop_buffer()
	elif pressed:
		if not lash(upward):
			buffer_left = LASH_BUFFER
			_buffer_up = upward
	elif buffer_left > 0.0:
		if lash(_buffer_up or upward):
			drop_buffer()
		else:
			buffer_left = maxf(buffer_left - delta, 0.0)


func _process(_delta: float) -> void:
	if active:
		queue_redraw()


func _draw() -> void:
	if not active:
		return
	var body := _player.get_node("Visual") as PlayerBody
	# The wiggle shifts the picture; the tip stays where it stuck.
	var shown := extension if up else extension - float(direction) * body.shake.x
	draw_rect(body.tongue_rect_up(shown) if up else body.tongue_rect(shown), PINK)
	if (phase == Phase.STICK or phase == Phase.CLIMB) and GameState.abilities.tongue_pad:
		draw_rect(body.pad_rect_up(shown) if up else body.pad_rect(shown), PINK)


func _reset_phase() -> void:
	phase = Phase.OUT
	_time = 0.0
	_back_from = 0.0
	_back_duration = 0.0
	_struck = false
	_climbable = false
	_struck_wall = false


## The tip has stopped going out. If it hit something and the tongue sticks, it
## holds there first; otherwise it turns for home. A lash that hits at once, with
## nothing out, has nothing to stick.
func _begin_return() -> void:
	if _try_climb():
		return
	if _struck and extension > 0.0 and GameState.abilities.tongue_stick > 0.0:
		phase = Phase.STICK
		_time = 0.0
		_stuck_at = tip().y if up else tip().x
		return
	_start_back()


## With Tongue Climb, a tip that stuck to something Freddy can hang from pulls him
## to it: `Player.begin_climb` works out where he hangs. False if the power is
## off, the surface is not one (an Imprint platform, a moving platform, a wall
## that has just broken, a ceiling when ceilings are off) or he may not stick
## now (he must land first).
func _try_climb() -> bool:
	var abilities := GameState.abilities
	if not abilities.tongue_climb or not _struck or not _climbable:
		return false
	if up and not abilities.climb_ceiling:
		return false
	var dir := Vector2(0.0, -1.0) if up else Vector2(float(direction), 0.0)
	var at := tip()
	if not _player.begin_climb(at, dir, abilities.climb_hold, abilities.climb_wiggle, abilities.climb_zip_speed, abilities.climb_land_to_restick):
		return false
	phase = Phase.CLIMB
	_time = 0.0
	_stuck_tip = at
	_stuck_breakable = _struck_wall
	return true


## Sets up the return from where the tip is: it takes `extension / (snap * speed)`
## seconds, along the curve `TongueMotion.remaining` gives.
func _start_back() -> void:
	phase = Phase.BACK
	_time = 0.0
	_back_from = extension
	_back_duration = TongueMotion.back_duration(extension, GameState.abilities)


func _move(delta: float) -> void:
	var abilities := GameState.abilities
	match phase:
		Phase.CLIMB:
			# The tip stays where it stuck while Freddy is pulled to it and hangs.
			if up:
				extension = maxf(0.0, _player.global_position.y - _stuck_tip.y - FRONT)
			else:
				extension = maxf(0.0, float(direction) * (_stuck_tip.x - _player.global_position.x) - FRONT)
			if not _player.climbing() and _player.jumped_off_climb():
				# A jump off the hang pulls the tongue in at once, so the next
				# lash is only the cooldown away.
				end()
				return
			if not _player.climbing() or not _surface_holds():
				_player.end_climb()
				_start_back()
			return
		Phase.STICK:
			_time += delta
			# The tip stays where it hit even if the player moves.
			if up:
				extension = maxf(0.0, _player.global_position.y - _stuck_at - FRONT)
			else:
				extension = maxf(0.0, float(direction) * (_stuck_at - _player.global_position.x) - FRONT)
			if _time >= abilities.tongue_stick - TongueMotion.EPSILON:
				_start_back()
			return
		Phase.BACK:
			_time += delta
			if _time >= _back_duration - TongueMotion.EPSILON:
				# The return hits nothing, so it needs no steps.
				end()
				return
			extension = _back_from * TongueMotion.remaining(_time / _back_duration, abilities)
			return
	var distance := TongueMotion.out_distance(_time, delta, abilities)
	_time += delta
	var steps := maxi(1, ceili(distance / STEP))
	for i in steps:
		extension = minf(extension + distance / float(steps), abilities.tongue_length)
		if _hit() or extension >= abilities.tongue_length:
			_begin_return()
			return


## Whether the tip has run into something, and if so what it did to it: a
## breakable wall is hit, and any solid stops the tongue with a puff. A tip that
## has left the room stops there with no puff.
func _hit() -> bool:
	_struck = false
	_climbable = false
	_struck_wall = false
	var room: Room = _world.current
	var at := tip()
	var size := TIP_UP if up else TIP
	var box := Rect2(at - size * 0.5, size)
	var wall := room.wall_at(box)
	if wall != null:
		var broke := room.hit_wall(wall, DevSession.wall_strength())
		_puff(at)
		_struck = true
		_struck_wall = true
		_climbable = GameState.abilities.climb_breakable and not broke
		return true
	var extra: Array[Rect2] = []
	var origin := room.position
	# The room's own solids are tested cell by cell in box_hit; only what is
	# not in them is passed along: door blocks, Imprint platforms and movers.
	for rect in room.block_rects():
		extra.append(Rect2(rect.position - origin, rect.size))
	for platform in _world.imprint.platforms:
		extra.append(Rect2(platform.rect.position - origin, platform.rect.size))
	for rect in room.mover_rects():
		extra.append(Rect2(rect.position - origin, rect.size))
	var local := Rect2(box.position - origin, box.size)
	# The room has already moved its platforms to this tick, which is where the
	# player finished the step, so the tongue tests the same moment the body does.
	var solid := bool(TongueReach.box_hit(room.info, local, extra)["solid"])
	if solid:
		_puff(at)
		_struck = true
		# Only a room solid or a door block can be hung from, not an Imprint
		# platform or a moving platform.
		_climbable = bool(TongueReach.box_hit(room.info, local, _block_extra(room))["solid"])
		return true
	return not Rect2(room.position, room.info.pixel_size).has_point(at)


## The abilities have changed (the dev tools, a pickup, a loadout): if what the
## hang depends on has been taken away, he drops at once and the tongue goes
## back in, with nothing given back. Numbers (the hold, the pull) apply from the
## next climb.
func _reconcile_abilities() -> void:
	if not active:
		return
	var abilities := GameState.abilities
	if not abilities.tongue_unlocked:
		_player.cancel_climb()
		clear()
		return
	if phase != Phase.CLIMB:
		return
	if not abilities.tongue_climb or (up and not abilities.climb_ceiling) or (_stuck_breakable and not abilities.climb_breakable):
		_player.cancel_climb()
		_start_back()


## The door blocks, in room pixels, as `TongueReach` takes them.
func _block_extra(room: Room) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in room.block_rects():
		out.append(Rect2(rect.position - room.position, rect.size))
	return out


## Whether what the tip stuck to is still there: a breakable wall standing, a
## room solid or a door block.
func _surface_holds() -> bool:
	var room: Room = _world.current
	var size := TIP_UP if up else TIP
	var box := Rect2(_stuck_tip - size * 0.5, size)
	if room.wall_at(box) != null:
		return true
	var local := Rect2(box.position - room.position, box.size)
	return bool(TongueReach.box_hit(room.info, local, _block_extra(room))["solid"])


## Two specks thrown back from where the tip stopped.
func _puff(at: Vector2) -> void:
	for _i in 2:
		var dust := Player.Dust.new()
		dust.position = at
		if up:
			dust.velocity = Vector2(randf_range(-20.0, 20.0), randf_range(5.0, 25.0))
		else:
			dust.velocity = Vector2(-float(direction) * randf_range(10.0, 30.0), randf_range(-25.0, 5.0))
		dust.life = 0.15
		_world.add_child(dust)
