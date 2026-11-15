extends Node

signal room_changed(room_id: String)
signal visited_changed
signal abilities_changed
signal tokens_changed
## Health pips were collected, spent or refilled.
signal health_changed
## An upgrade was given by a pickup or a 3TM. Not emitted for dev edits or loads.
signal upgrade_granted(id: String)

## Most tokens the player can carry at once.
const TOKEN_CAP := Progression.TOKEN_CAP
## Hearts every player has from the start. Collected pips add to it.
const BASE_HEALTH := Progression.BASE_HEALTH

var current_room_id := ""
var visited := {}
## How zoomed the map is (MapView.OUT, MIDDLE or IN). The player's choice
## stays with the game, so a new game starts it at the middle again.
var map_zoom := MapView.MIDDLE
var abilities := Abilities.new()
## Things the player has done that stay done: "pickup:<id>" for each pickup
## collected and "token:<id>" for each token taken. Keys are text and values
## are true.
var flags := {}
## Tokens carried now.
var tokens := 0
## How many tokens each 3TM holds, by its id. At three it has given its upgrade.
var machines := {}
## The save room the player last entered, or "" before they have entered one.
## Dying on the last heart puts them back at its save machine.
var save_room := ""
## Full hearts now. The player starts with one. Dying with two or more empties
## one and puts them back on the last safe floor; dying on the last heart
## empties it too (it blinks out) and sends them to their save room, which fills
## every heart again. So health is 0 only for that moment, or after a dev edit.
var health := BASE_HEALTH
## Hearts held, full or empty: the base heart plus the pips collected. This is
## the length of the HUD's frame. Never below 1 and never below `health`.
var max_health := BASE_HEALTH


func visit(room_id: String) -> void:
	current_room_id = room_id
	var is_new := not visited.has(room_id)
	visited[room_id] = true
	room_changed.emit(room_id)
	if is_new:
		visited_changed.emit()


func has_flag(key: String) -> bool:
	return flags.has(key)


## The flag that says the player has been through `door` of room `room_id`.
static func door_flag(room_id: String, door: Door) -> String:
	return "door:%s:%d,%d" % [room_id, door.rect.position.x, door.rect.position.y]


## Whether the player has been through `door` of room `room_id`, from either side.
func door_used(room_id: String, door: Door) -> bool:
	return flags.has(door_flag(room_id, door))


## The player went through `door` of room `room_id`. Both openings of the pair
## are marked, so the map shows the far side as taken too. The map redraws.
func use_door(room_id: String, door: Door) -> void:
	var fresh := _mark_door(room_id, door)
	var far_room: RoomInfo = _rooms().get(door.dest_id)
	if far_room != null:
		var far := far_room.door_by_rect(door.dest_rect)
		if far != null:
			fresh = _mark_door(door.dest_id, far) or fresh
	if fresh:
		visited_changed.emit()


## The world's rooms, or none when the world is not loaded (a test of this
## script on its own has no WorldData autoload).
func _rooms() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var data := tree.root.get_node_or_null("WorldData") if tree != null else null
	return {} if data == null else data.rooms


func _mark_door(room_id: String, door: Door) -> bool:
	var key := door_flag(room_id, door)
	if flags.has(key):
		return false
	flags[key] = true
	return true


## A save from before doors were remembered has none. Doors whose room and
## destination are both visited are taken to have been used, so the map does not
## turn red everywhere. Does nothing once any door is remembered.
func _seed_doors() -> void:
	if visited.size() < 2:
		return
	for key in flags:
		if String(key).begins_with("door:"):
			return
	for room_id in visited:
		var info: RoomInfo = _rooms().get(room_id)
		if info == null:
			continue
		for door in info.exits:
			if not door.dest_id.is_empty() and visited.has(door.dest_id):
				_mark_door(room_id, door)


## Takes a pickup: remembers it and applies its upgrade. Returns a line to
## show the player.
func collect(def: EntityDef) -> String:
	flags[Pickup.flag_for(def)] = true
	return grant(String(def.props["upgrade"]), String(def.props.get("value", "")))


## Applies upgrade `id` with the value written as `text`. Returns a line to
## show the player.
func grant(id: String, text: String) -> String:
	var upgrade := Upgrades.get_def(id)
	var value: Variant = Upgrades.parse_value(id, text)
	if abilities.apply(upgrade, value):
		abilities_changed.emit()
	upgrade_granted.emit(id)
	if upgrade.has_message:
		return upgrade.message
	return "%s +1" % upgrade.title.capitalize()


func tokens_full() -> bool:
	return tokens >= TOKEN_CAP


## Picks up a token: remembers it and carries it. False, and nothing taken, if
## the player is already carrying as many as they can.
func take_token(def: EntityDef) -> bool:
	if tokens_full():
		return false
	flags[Token.flag_for(def)] = true
	tokens += 1
	tokens_changed.emit()
	return true


## Takes a health pip: one more death that goes back to the last safe floor.
## The HUD shows it, so there is no line.
func take_health(def: EntityDef) -> void:
	flags[HealthPip.flag_for(def)] = true
	_add_pip()


## One more heart in the frame, and full.
func _add_pip() -> void:
	max_health += 1
	health += 1
	health_changed.emit()


## A death: one heart empties, the last one included. The frame keeps its length.
func spend_health() -> void:
	health = maxi(0, health - 1)
	health_changed.emit()


## A save room fills every heart again.
func refill_health() -> void:
	if health == max_health:
		return
	health = max_health
	health_changed.emit()


## What a 3TM gives when it is fed: its upgrade, or a health pip with
## `prize=health`. Returns a line to show the player, or "" for a pip, which the
## HUD shows. A machine's fill count is kept, so a spent one never gives it twice.
func machine_prize(def: EntityDef) -> String:
	if def.props.has("prize"):
		_add_pip()
		return ""
	return grant(String(def.props["upgrade"]), String(def.props.get("value", "")))


## Gives up one carried token, for a 3TM to take.
func spend_token() -> void:
	tokens = maxi(0, tokens - 1)
	tokens_changed.emit()


## The saved shape. Where the player stands is added by Save, not here.
func to_dict() -> Dictionary:
	return snapshot().to_dict()


func snapshot() -> Progression:
	var out := Progression.new()
	out.visited = visited.duplicate()
	out.abilities = abilities.copy()
	out.flags = flags.duplicate()
	out.tokens = tokens
	out.machines = machines.duplicate()
	out.map_zoom = map_zoom
	out.save_room = save_room
	out.health = health
	out.max_health = max_health
	return out


## Replaces the state with what to_dict wrote. Anything unreadable is left
## out, so a damaged save gives a smaller state and not a crash.
func load_dict(data: Dictionary) -> void:
	restore(Progression.from_dict(data))


func restore(progress: Progression) -> void:
	visited = progress.visited.duplicate()
	flags = progress.flags.duplicate()
	machines = progress.machines.duplicate()
	tokens = progress.tokens
	map_zoom = progress.map_zoom
	save_room = progress.save_room
	health = progress.health
	max_health = progress.max_health
	abilities = progress.abilities.copy()
	_seed_doors()
	tokens_changed.emit()
	health_changed.emit()
	abilities_changed.emit()
	visited_changed.emit()


func set_flag(key: String) -> void:
	flags[key] = true


func set_machine_fill(id: String, filled: int) -> void:
	machines[id] = filled


func set_save_room(id: String) -> void:
	save_room = id


func set_map_zoom(level: int) -> void:
	map_zoom = level


func reset() -> void:
	load_dict({})


## Exact dev editing changes powers/resources without replacing progression.
func set_loadout(loadout: Dictionary) -> void:
	abilities = Abilities.from_dict(loadout["abilities"])
	tokens = int(loadout["tokens"])
	health = int(loadout["health"])
	max_health = maxi(BASE_HEALTH, maxi(health, int(loadout.get("max_health", 0))))
	abilities_changed.emit()
	tokens_changed.emit()
	health_changed.emit()
