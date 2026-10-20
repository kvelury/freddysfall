extends Node

signal room_changed(room_id: String)
signal visited_changed
signal abilities_changed
signal tokens_changed

## Most tokens the player can carry at once.
const TOKEN_CAP := 3

var current_room_id := ""
var visited := {}
## How zoomed the map is (MapView.OUT, MIDDLE or IN). The player's choice
## stays with the game, so a new game starts it at the middle again.
var map_zoom := MapView.MIDDLE
var abilities := Abilities.new()
## Things the player has done that stay done: "pickup:<id>" for each pickup
## collected. Keys are text and values are true.
var flags := {}
## Tokens carried now.
var tokens := 0
## How many tokens each 3TM holds, by its id. At three it has given its upgrade.
var machines := {}


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
	if upgrade.has("message"):
		return String(upgrade["message"])
	return "%s: %s" % [upgrade["name"], value]


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
			machines[String(id)] = clampi(int(held[id]), 0, 3)
	tokens = clampi(int(data.get("tokens", 0)), 0, TOKEN_CAP)
	map_zoom = MapView.clamp_level(int(data.get("map_zoom", MapView.MIDDLE)))
	tokens_changed.emit()
	var saved = data.get("abilities", {})
	abilities = Abilities.from_dict(saved if saved is Dictionary else {})
	abilities_changed.emit()
	visited_changed.emit()


func reset() -> void:
	load_dict({})
