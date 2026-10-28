extends Node

## Session boundary for all cheats. Normal saves are guarded here and in Save,
## and snapshots contain copied values, never nodes from a previous attempt.

enum Mode { NORMAL, ROOM_TEST, DEV_TEST }

var mode := Mode.NORMAL
var available := false
var bypass := false
## Imprint platforms keep their width and show the dash clock. A comparison
## switch for a dev test: not saved, not in a loadout.
var classic_imprint := false
## How many shots break a breakable wall in a dev test, or 0 for the default
## (BreakableWall.DEFAULT_STRENGTH). World tuning and not an ability, so it is
## a session setting like Classic Imprint: it survives retries, is not saved
## and is not in a loadout, and End playtest or a fresh boot resets it.
var wall_strength_override := 0
const MAX_WALL_STRENGTH := 99
var retry_on_death := false
var target := ""
var baseline := {}
var loadout := {}
var replacing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func isolated() -> bool:
	return mode != Mode.NORMAL or replacing


## Called only for an initial boot, never by a retry or End playtest rebuild.
func configure(dev: bool, room_test: bool) -> void:
	available = OS.is_debug_build() or dev
	mode = Mode.DEV_TEST if dev else (Mode.ROOM_TEST if room_test else Mode.NORMAL)
	bypass = false
	classic_imprint = false
	wall_strength_override = 0
	retry_on_death = false
	baseline = {}
	loadout = {}
	target = ""
	replacing = false


## Back to a normal game, for the main menu. Unlike `configure` it keeps
## `available`, so a `?dev=1` player still has F2 after Continue.
func reset_to_normal() -> void:
	mode = Mode.NORMAL
	bypass = false
	classic_imprint = false
	wall_strength_override = 0
	retry_on_death = false
	baseline = {}
	loadout = {}
	target = ""
	replacing = false


func enter(world: Node) -> String:
	if not available or replacing or world.is_busy():
		return "Wait for the current animation to finish."
	if mode != Mode.DEV_TEST:
		mode = Mode.DEV_TEST
		capture(world.current.info.id)
	return ""


func capture(room_id: String) -> void:
	target = room_id
	baseline = GameState.to_dict().duplicate(true)
	loadout = DevCatalog.capture(baseline)


## Patch contains only fields the user edited. Resource consumption and pickup
## rewards in other fields do not accidentally become the retry loadout.
func apply(world: Node, patch: Dictionary) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	var selected := loadout.duplicate(true)
	var live := DevCatalog.capture(GameState.to_dict())
	var changed_imprint := false
	for key in patch:
		if key == "abilities":
			if not patch[key] is Dictionary:
				return "Invalid abilities."
			for stat in patch[key]:
				var control: Dictionary = DevCatalog.controls().get(stat, {})
				if control.get("type") == "unsupported":
					return String(control["reason"])
				if stat != "air_jumps" and live["abilities"].get(stat) != patch[key][stat]:
					changed_imprint = true
				live["abilities"][stat] = patch[key][stat]
				selected["abilities"][stat] = patch[key][stat]
		elif DevCatalog.RESOURCES.has(key):
			live[key] = patch[key]
			selected[key] = patch[key]
		else:
			return "Unknown loadout field: %s" % key
	var error := DevCatalog.validate(live)
	if error.is_empty():
		error = DevCatalog.validate(selected)
	if not error.is_empty():
		return error
	GameState.set_loadout(live)
	loadout = selected
	if changed_imprint:
		world.imprint.clear(false)
		world.imprint.sync_solids()
	return ""


func start(world: Node, room_id: String, fresh := false) -> String:
	if not available or mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	if not WorldData.rooms.has(room_id):
		return "No such room: %s" % room_id
	target = room_id
	baseline = {} if fresh else GameState.to_dict().duplicate(true)
	_replace_later(world, DevCatalog.with_loadout(baseline, loadout))
	return ""


func retry(world: Node, after_death := false) -> String:
	if mode != Mode.DEV_TEST or replacing or (world.is_busy() and not after_death) or not WorldData.rooms.has(target):
		return "No test is ready to retry."
	_replace_later(world, DevCatalog.with_loadout(baseline, loadout))
	return ""


func set_bypass(world: Node, on: bool) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	var room: Room = world.current
	if not on and not ExitRules.met(room.info, GameState.flags):
		for door in room.info.exits:
			var rect := Grid.cell_rect(door.rect)
			rect.position += room.position
			if rect.intersects(world.player.body_rect()):
				return "Move clear of the doorway first."
	bypass = on
	room.set_door_override(on, GameState.flags)
	world.imprint.sync_solids()
	return ""


## Whether a platform placed now keeps its width. Only in a dev test, so normal
## play can never see the switch.
func classic_imprint_active() -> bool:
	return mode == Mode.DEV_TEST and classic_imprint


func set_classic_imprint(world: Node, on: bool) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	classic_imprint = on
	# Platforms of the other kind must not stand beside the new ones.
	world.imprint.clear(false)
	world.imprint.sync_solids()
	return ""


## Shots a breakable wall takes to break: the dev test's setting if there is
## one, else the default.
func wall_strength() -> int:
	if mode == Mode.DEV_TEST and wall_strength_override > 0:
		return wall_strength_override
	return BreakableWall.DEFAULT_STRENGTH


func set_wall_strength(world: Node, shots: int) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	if shots < 1 or shots > MAX_WALL_STRENGTH:
		return "Wall strength is a whole number from 1 to %d." % MAX_WALL_STRENGTH
	wall_strength_override = shots
	return ""


func set_retry_on_death(world: Node, on: bool) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	retry_on_death = on
	return ""


func end(world: Node) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	replacing = true
	_replace.call_deferred(world, {}, true)
	return ""


func _replace_later(world: Node, state: Dictionary) -> void:
	replacing = true
	_replace.call_deferred(world, state, false)


func _replace(world: Node, state: Dictionary, normal: bool) -> void:
	var parent := world.get_parent()
	var was_main := get_tree().current_scene == world
	# Free the world (including its timers/tweens) before restoring normal access.
	world.free()
	get_tree().paused = false
	if normal:
		mode = Mode.NORMAL
		bypass = false
		classic_imprint = false
		wall_strength_override = 0
		retry_on_death = false
		baseline = {}
		loadout = {}
		GameState.reset()
	else:
		GameState.load_dict(state)
	replacing = false
	var next: Node = load("res://src/world/world.tscn").instantiate()
	next.dev_rebuild = true
	next.dev_resume_normal = normal
	parent.add_child(next)
	if was_main:
		get_tree().current_scene = next
