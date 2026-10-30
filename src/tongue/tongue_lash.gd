class_name TongueLash
extends Node2D

## Tongue Lash. Once it is found, `lash` sends Freddy's tongue out of the notch
## in the front of his body, the way he faces, and pulls it back in. The tip
## goes out until it meets something solid or runs out of length
## (`Abilities.tongue_length`), and then the tongue returns at the same speed.
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

## The headless tests set `scripted` and lash with `scripted_lash`.
var scripted := false
var scripted_lash := false

## Whether a tongue is out, going or coming back.
var active := false
## 1 right, -1 left: the way the tongue was sent.
var direction := 1
## Pixels from the front of the body to the tip.
var extension := 0.0
## Whether the tongue is coming back in.
var retracting := false
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
	retracting = false
	# A lash against a wall the player is pressed to hits it at once.
	if _hit():
		retracting = true
	queue_redraw()
	return true


## Pulls the tongue in at once and starts the wait for the next lash.
func end() -> void:
	if active:
		cooldown_left = GameState.abilities.tongue_cooldown
	active = false
	extension = 0.0
	retracting = false
	queue_redraw()


## Removes the tongue and the wait for the next lash.
func clear() -> void:
	active = false
	extension = 0.0
	retracting = false
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


func _move(delta: float) -> void:
	var distance := GameState.abilities.tongue_speed * delta
	var steps := maxi(1, ceili(distance / STEP))
	for i in steps:
		var move := distance / float(steps)
		if retracting:
			extension -= move
			if extension <= 0.0:
				end()
				return
			continue
		extension = minf(extension + move, GameState.abilities.tongue_length)
		if _hit() or extension >= GameState.abilities.tongue_length:
			retracting = true
			return


## Whether the tip has run into something, and if so what it did to it: a
## breakable wall is hit, and any solid stops the tongue with a puff. A tip that
## has left the room stops there with no puff.
func _hit() -> bool:
	var room: Room = _world.current
	var at := tip()
	var box := Rect2(at - TIP * 0.5, TIP)
	var wall := room.wall_at(box)
	if wall != null:
		room.hit_wall(wall, DevSession.wall_strength())
		_puff(at)
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
