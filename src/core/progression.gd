class_name Progression
extends RefCounted

## What a save remembers, apart from where the player is standing. The game
## state holds one, and the save file is this plus the room and the position.
## A new thing the game remembers is a var here: to_dict and from_dict follow
## these lines, and save_test checks that every one of them is written.

## Most tokens the player can carry at once.
const TOKEN_CAP := 3
## Hearts every player has from the start. Collected pips add to it.
const BASE_HEALTH := 1

var visited := {}
var abilities := Abilities.new()
## "pickup:<id>", "token:<id>", "save:<id>", "health:<id>", "title:<id>".
var flags := {}
var tokens := 0
var machines := {}
var map_zoom := MapView.MIDDLE
var save_room := ""
var health := BASE_HEALTH
var max_health := BASE_HEALTH


func to_dict() -> Dictionary:
	return {
		"visited": visited.keys(),
		"abilities": abilities.to_dict(),
		"flags": flags.keys(),
		"tokens": tokens,
		"machines": machines.duplicate(),
		"map_zoom": map_zoom,
		"save_room": save_room,
		"health_base": BASE_HEALTH,
		"health": health,
		"max_health": max_health,
	}


## A progression read from a save. Missing and unknown keys stay at their
## starting values, and a save from before the base heart gains it.
static func from_dict(data: Dictionary) -> Progression:
	var out := Progression.new()
	for id in data.get("visited", []):
		out.visited[String(id)] = true
	for key in data.get("flags", []):
		out.flags[String(key)] = true
	var held = data.get("machines", {})
	if held is Dictionary:
		for id in held:
			out.machines[String(id)] = clampi(int(held[id]), 0, TokenMachine.COST)
	out.tokens = clampi(int(data.get("tokens", 0)), 0, TOKEN_CAP)
	out.map_zoom = MapView.clamp_level(int(data.get("map_zoom", MapView.MIDDLE)))
	var saved_room = data.get("save_room", "")
	out.save_room = String(saved_room) if saved_room is String else ""
	out.health = maxi(0, int(data.get("health", 0)))
	# A save from before the base heart counted pips only, so it gains the base
	# heart. A save with the key already counts it. An empty dict is a new game.
	var shift := 0 if data.has("health_base") or data.is_empty() else BASE_HEALTH
	if data.is_empty():
		out.health = BASE_HEALTH
	out.health += shift
	out.max_health = maxi(out.health, int(data.get("max_health", 0)) + shift)
	out.max_health = maxi(BASE_HEALTH, out.max_health)
	out.health = mini(out.health, out.max_health)
	var saved = data.get("abilities", {})
	out.abilities = Abilities.from_dict(saved if saved is Dictionary else {})
	return out


func copy() -> Progression:
	return from_dict(to_dict())
