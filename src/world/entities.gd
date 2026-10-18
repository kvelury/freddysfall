class_name Entities
extends RefCounted

## The kinds of thing a room legend can place. The parser asks here whether a
## legend line is valid, and the room asks here to build the thing. Adding a
## kind means a line in TYPES, a script under src/world/entities/, and a case
## in create.
##
## "required" and "optional" are the keys a legend line may carry besides
## id (always required) and the type itself.

const TYPES := {
	"pickup": {"required": ["upgrade", "value"], "optional": []},
}


static func is_known(type: String) -> bool:
	return TYPES.has(type)


## What is wrong with a legend line's settings, as sentences. `def` has its
## type, id and props filled in.
static func problems(def: EntityDef) -> Array[String]:
	var out: Array[String] = []
	if not is_known(def.type):
		out.append("\"%s\" is not a kind of thing a legend can place (kinds: %s)" % [def.type, ", ".join(TYPES.keys())])
		return out
	if def.id.is_empty():
		out.append("%s needs an id=, a name that stays the same for good" % def.type)
	var spec: Dictionary = TYPES[def.type]
	for key in spec["required"]:
		if not def.props.has(key):
			out.append("%s %s needs %s=" % [def.type, def.id, key])
	for key in def.props:
		if not spec["required"].has(key) and not spec["optional"].has(key):
			out.append("%s %s has %s=, which %s does not use" % [def.type, def.id, key, def.type])
	if out.is_empty() and def.type == "pickup":
		var message := Upgrades.check(String(def.props["upgrade"]), String(def.props["value"]))
		if not message.is_empty():
			out.append("pickup %s: %s" % [def.id, message])
	return out


## Whether the thing is in the world, given the player's flags. A pickup is
## gone once it has been collected. This takes the flags, not GameState, so the
## parser and the tests can use the registry without the game running.
static func present(def: EntityDef, flags: Dictionary) -> bool:
	match def.type:
		"pickup":
			return not flags.has(Pickup.flag_for(def))
	return true


static func create(def: EntityDef) -> Node2D:
	match def.type:
		"pickup":
			return Pickup.new(def)
	return null
