class_name TongueLash
extends Node2D

## Tongue Lash. Once it is found, `lash` sends Freddy's tongue out of the notch
## in the front of his body, the way he faces, and pulls it back in. The tip
## goes out until it meets something solid or runs out of length
## (`Abilities.tongue_length`), and then the tongue snaps back. How it moves, out
## and in, is `TongueMotion`'s: a creep, a snap, an optional stick on what it hit,
## a return that averages `Abilities.tongue_snap` times `tongue_speed`, and an
## optional wobble as it seats. With the stats at their starting values it goes
## out at a steady `tongue_speed` and comes back speeding up.
## What the tip meets is dealt with as the gun's shot was: a breakable wall takes a hit
## (see BreakableWall), anything else stops it. One lash hits at most one thing.
## There is no aiming, so a player who wants to reach higher jumps first.
##
## It is a child of the world and uses its `current` room, `player` and
## `imprint`. A lash belongs to the room it was made in: leaving, dying and
## warping clear it. Turning round, or the world going busy, cuts it short.

## The tip moves in steps no longer than this, so a fast one cannot skip a cell.
const STEP := 4.0
## Half the body's width, in pixels: the tongue's length is counted from the
## front of the body.
const FRONT := 5.0
## The mouth's height above the body's centre, in pixels. The hit is made here
## whatever picture is on show; only the drawing follows the picture.
const MOUTH_RISE := 1.5
## The size of the tip's box, in pixels.
const TIP := Vector2(3.0, 1.0)
const PINK := Color("ff6fa8")

## The four parts of a lash. OUT is the creep and the snap; STICK holds the tip on
## what it hit; BACK is the return; SEAT is the wobble after it.
enum Phase { OUT, STICK, BACK, SEAT }

## The headless tests set `scripted` and lash with `scripted_lash`.
var scripted := false
var scripted_lash := false

## Whether a tongue is out, going or coming back.
var active := false
## 1 right, -1 left: the way the tongue was sent.
var direction := 1
## Pixels from the front of the body to the tip.
var extension := 0.0
## Which part of the lash the tongue is in.
var phase := Phase.OUT
## Whether the tongue has turned for home: stuck, coming back or seating.
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
## The world x the tip stuck to.
var _stuck_x := 0.0
## Seconds before another lash may be made. It runs only while the tongue is in.
var cooldown_left := 0.0

var _world: Node
var _player: Player


func _ready() -> void:
	# Drawn from _process, in whole pixels.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world = get_parent()
	_player = _world.get_node("Player")


## Whether a press sends the tongue out now: Tongue Lash has been found, none is
## out, the last has been back long enough, and the player is in control in a room.
func can_lash() -> bool:
	return GameState.abilities.tongue_unlocked and not active and cooldown_left <= 0.0 and not _world.gameplay_input_blocked() and _player.input_enabled and _world.current != null and not _world.is_busy()


## Lashes if it may. Returns whether it did.
func lash() -> bool:
	if not can_lash():
		return false
	active = true
	direction = _player.facing
	extension = 0.0
	_reset_phase()
	# A lash against a wall the player is pressed to hits it at once.
	if _hit():
		_begin_return()
	queue_redraw()
	return true


## Pulls the tongue in at once and starts the wait for the next lash.
func end() -> void:
	if active:
		cooldown_left = GameState.abilities.tongue_cooldown
	active = false
	extension = 0.0
	_reset_phase()
	queue_redraw()


## Removes the tongue and the wait for the next lash.
func clear() -> void:
	active = false
	extension = 0.0
	_reset_phase()
	cooldown_left = 0.0
	queue_redraw()


## The world position of the tip.
func tip() -> Vector2:
	return _player.global_position + Vector2(float(direction) * (FRONT + extension), -MOUTH_RISE)


func _physics_process(delta: float) -> void:
	if _world.current == null or _world.is_busy():
		end()
		return
	if active and _player.facing != direction:
		end()
	if not active:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
	else:
		_move(delta)
	var pressed := scripted_lash if scripted else Input.is_action_just_pressed("lash")
	scripted_lash = false
	if pressed:
		lash()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var body := _player.get_node("Visual") as PlayerBody
	draw_rect(body.tongue_rect(extension), PINK)
	if phase == Phase.STICK and GameState.abilities.tongue_pad:
		draw_rect(body.pad_rect(extension), PINK)


func _reset_phase() -> void:
	phase = Phase.OUT
	_time = 0.0
	_back_from = 0.0
	_back_duration = 0.0
	_struck = false


## The tip has stopped going out. If it hit something and the tongue sticks, it
## holds there first; otherwise it turns for home. A lash that hits at once, with
## nothing out, has nothing to stick.
func _begin_return() -> void:
	if _struck and extension > 0.0 and GameState.abilities.tongue_stick > 0.0:
		phase = Phase.STICK
		_time = 0.0
		_stuck_x = tip().x
		return
	_start_back()


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
		Phase.STICK:
			_time += delta
			# The tip stays where it hit even if the player moves.
			extension = maxf(0.0, float(direction) * (_stuck_x - _player.global_position.x) - FRONT)
			if _time >= abilities.tongue_stick - TongueMotion.EPSILON:
				_start_back()
			return
		Phase.BACK:
			_time += delta
			if _time >= _back_duration - TongueMotion.EPSILON:
				# The return hits nothing, so it needs no steps.
				extension = 0.0
				if abilities.tongue_wobble > 0.0:
					phase = Phase.SEAT
					_time = 0.0
				else:
					end()
				return
			extension = _back_from * TongueMotion.remaining(_time / _back_duration, abilities)
			return
		Phase.SEAT:
			_time += delta
			if _time >= TongueMotion.SEAT_TIME - TongueMotion.EPSILON:
				end()
				return
			extension = TongueMotion.seat_offset(_time / TongueMotion.SEAT_TIME, abilities.tongue_wobble)
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
	var room: Room = _world.current
	var at := tip()
	var box := Rect2(at - TIP * 0.5, TIP)
	var wall := room.wall_at(box)
	if wall != null:
		room.hit_wall(wall, DevSession.wall_strength())
		_puff(at)
		_struck = true
		return true
	var solid := false
	for rect in room.world_rects():
		if rect.intersects(box):
			solid = true
			break
	if not solid:
		for platform in _world.imprint.platforms:
			if platform.rect.intersects(box):
				solid = true
				break
	if not solid:
		for rect in room.mover_rects():
			if rect.intersects(box):
				solid = true
				break
	if solid:
		_puff(at)
		_struck = true
		return true
	return not Rect2(room.position, room.info.pixel_size).has_point(at)


## Two specks thrown back from where the tip stopped.
func _puff(at: Vector2) -> void:
	for _i in 2:
		var dust := Player.Dust.new()
		dust.position = at
		dust.velocity = Vector2(-float(direction) * randf_range(10.0, 30.0), randf_range(-25.0, 5.0))
		dust.life = 0.15
		_world.add_child(dust)
