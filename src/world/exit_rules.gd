class_name ExitRules
extends RefCounted

## The conditions a room can put on leaving it. A room names one in its header
## (`exits: pickups`). While the rule is not met every door in the room is
## blocked, and the player can only leave once it is. Adding a rule means a line
## in RULES and a case in `met`.

const OPEN := "open"
const PICKUPS := "pickups"
const SAVED := "saved"

const RULES := {
	"open": "The doors are always open.",
	"pickups": "The doors open once every pickup and token in the room has been taken.",
	"saved": "The doors open once the room's save machine has been used.",
}


static func is_known(rule: String) -> bool:
	return RULES.has(rule)


## What is wrong with a room's rule, as a sentence, or "" if nothing is.
static func problem(rule: String, info: RoomInfo) -> String:
	if not is_known(rule):
		return "exits: \"%s\" is not a rule (rules: %s)" % [rule, ", ".join(RULES.keys())]
	if rule == PICKUPS and not info.entities.any(func(def: EntityDef) -> bool: return Entities.is_collectible(def)):
		return "exits: pickups, but the room has no pickup or token to take"
	if rule == SAVED and not info.entities.any(func(def: EntityDef) -> bool: return def.type == "save"):
		return "exits: saved, but the room has no save machine"
	return ""


## Whether the doors of room `info` may be used, given the player's `flags`.
## This takes the flags and not GameState, so the solver and the tests can ask
## without the game running.
static func met(info: RoomInfo, flags: Dictionary) -> bool:
	match info.exit_rule:
		PICKUPS:
			for def in info.entities:
				if Entities.is_collectible(def) and Entities.present(def, flags):
					return false
		SAVED:
			for def in info.entities:
				if def.type == "save" and not flags.has(SaveMachine.flag_for(def)):
					return false
	return true
