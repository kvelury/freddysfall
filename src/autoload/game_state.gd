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
const TOKEN_CAP := 3

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
## Dying with no health puts them back at its save machine.
var save_room := ""
## Health pips held now. The player starts with none. Dying with one or more
## empties one and puts them back on the last safe floor; dying with none sends
## them to their save room. A save room fills them all again.
var health := 0
## Health pips collected: the length of the HUD's bar. Never below `health`.
var max_health := 0


func visit(room_id: String) -> void:
	current_room_id = room_id
	var is_new := not visited.has(room_id)
	visited[room_id] = true
	room_changed.emit(room_id)
	if is_new:
		visited_changed.emit()


func has_flag(key: String) -> bool:
	return flags.has(key)


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
	if upgrade.has("message"):
		return String(upgrade["message"])
	return "%s +1" % String(upgrade["name"]).capitalize()


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


## One more pip in the bar, and full.
func _add_pip() -> void:
	max_health += 1
	health += 1
	health_changed.emit()


## A death with health: one pip empties. The bar keeps its length.
func spend_health() -> void:
	health = maxi(0, health - 1)
	health_changed.emit()


## A save room fills every pip again.
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


func to_dict() -> Dictionary:
	return {
		"visited": visited.keys(),
		"abilities": abilities.to_dict(),
		"flags": flags.keys(),
		"tokens": tokens,
		"machines": machines.duplicate(),
		"map_zoom": map_zoom,
		"save_room": save_room,
		"health": health,
		"max_health": max_health,
	}


## Replaces the state with what to_dict wrote. Anything unreadable is left
## out, so a damaged save gives a smaller state and not a crash.
func load_dict(data: Dictionary) -> void:
	visited = {}
	for id in data.get("visited", []):
		visited[String(id)] = true
	flags = {}
	for key in data.get("flags", []):
		flags[String(key)] = true
	machines = {}
	var held = data.get("machines", {})
	if held is Dictionary:
		for id in held:
			machines[String(id)] = clampi(int(held[id]), 0, TokenMachine.COST)
	tokens = clampi(int(data.get("tokens", 0)), 0, TOKEN_CAP)
	map_zoom = MapView.clamp_level(int(data.get("map_zoom", MapView.MIDDLE)))
	var saved_room = data.get("save_room", "")
	save_room = String(saved_room) if saved_room is String else ""
	health = maxi(0, int(data.get("health", 0)))
	# A save from before the bar had a length: every pip held was collected.
	max_health = maxi(health, int(data.get("max_health", 0)))
	tokens_changed.emit()
	health_changed.emit()
	var saved = data.get("abilities", {})
	abilities = Abilities.from_dict(saved if saved is Dictionary else {})
	abilities_changed.emit()
	visited_changed.emit()


func reset() -> void:
	load_dict({})


## Exact dev editing changes powers/resources without replacing progression.
func set_loadout(loadout: Dictionary) -> void:
	abilities = Abilities.from_dict(loadout["abilities"])
	tokens = int(loadout["tokens"])
	health = int(loadout["health"])
	max_health = maxi(health, int(loadout.get("max_health", 0)))
	abilities_changed.emit()
	tokens_changed.emit()
	health_changed.emit()
