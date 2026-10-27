class_name Gun
extends Node2D

## The gun. Once it is found, `shoot` fires a shot from the player's body the
## way they face. A shot flies straight until it meets something solid: a
## breakable wall takes a hit (see BreakableWall), anything else stops it. There
## is no aiming, so a player who wants to shoot higher jumps first.
##
## It is a child of the world and uses its `current` room, `player` and
## `imprint`. Shots belong to the room they were fired in: leaving, dying and
## warping clear them.

## A shot moves in steps no longer than this, so a fast one cannot skip a cell.
const STEP := 4.0
## How far in front of the body's centre a shot starts, in pixels: just outside
## the body, and inside a wall the player is pressed against.
const MUZZLE := 6.0

## The headless tests set `scripted` and fire with `scripted_fire`.
var scripted := false
var scripted_fire := false

## The shots in flight, oldest first.
var shots: Array[Shot] = []
## Seconds before another shot may be fired.
var cooldown_left := 0.0

var _world: Node
var _player: Player


func _ready() -> void:
	# Drawn from _process, in whole pixels.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world = get_parent()
	_player = _world.get_node("Player")


## Whether a press fires a shot now: the gun has been found, the player is in
## control in a room, and the last shot is far enough behind.
func can_fire() -> bool:
	return GameState.abilities.gun_unlocked and cooldown_left <= 0.0 and not _world.gameplay_input_blocked() and _player.input_enabled and _world.current != null and not _world.is_busy()


## Fires a shot if it may. Returns whether it did.
func fire() -> bool:
	if not can_fire():
		return false
	var abilities := GameState.abilities
	var start := _player.global_position + Vector2(float(_player.facing) * MUZZLE, 0.0)
	var shot := Shot.new(start, _player.facing, abilities.gun_shot_speed)
	cooldown_left = abilities.gun_cooldown
	# A shot fired point blank against a wall hits it at once.
	if _hit(shot):
		return true
	shots.append(shot)
	queue_redraw()
	return true


## Removes every shot and the wait for the next.
func clear() -> void:
	shots.clear()
	cooldown_left = 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _world.current == null or _world.is_busy():
		return
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	_move_shots(delta)
	var pressed := scripted_fire if scripted else Input.is_action_just_pressed("shoot")
	scripted_fire = false
	if pressed:
		fire()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for shot in shots:
		var box := shot.rect()
		draw_rect(Rect2(box.position.round(), box.size), Color.WHITE)


func _move_shots(delta: float) -> void:
	var gone: Array[Shot] = []
	for shot in shots:
		var distance := shot.speed * delta
		var steps := maxi(1, ceili(distance / STEP))
		for i in steps:
			shot.position.x += float(shot.direction) * distance / float(steps)
			if _hit(shot):
				gone.append(shot)
				break
	for shot in gone:
		shots.erase(shot)


## Whether `shot` has run into something, and if so what it did to it: a
## breakable wall is hit, and any solid ends the shot with a puff. A shot that
## has left the room is gone with no puff.
func _hit(shot: Shot) -> bool:
	var room: Room = _world.current
	var box := shot.rect()
	var wall := room.wall_at(box)
	if wall != null:
		room.hit_wall(wall, DevSession.wall_strength())
		_puff(shot)
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
		_puff(shot)
		return true
	return not Rect2(room.position, room.info.pixel_size).has_point(shot.position)


## Two specks thrown back from where the shot stopped.
func _puff(shot: Shot) -> void:
	for _i in 2:
		var dust := Player.Dust.new()
		dust.position = shot.position
		dust.velocity = Vector2(-float(shot.direction) * randf_range(10.0, 30.0), randf_range(-25.0, 5.0))
		dust.life = 0.15
		_world.add_child(dust)
