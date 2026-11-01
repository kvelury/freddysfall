class_name Entities
extends RefCounted

## The kinds of thing a room legend can place. The parser asks here whether a
## legend line is valid, and the room asks here to build the thing. Adding a
## kind means a line in TYPES, a script under src/world/entities/, and a case
## in create. A moving platform and a breakable wall are the kinds drawn as more
## than one cell: the room parser turns a platform into a PlatformPath, and a
## breakable wall's cells go to RoomInfo.breakables; the room builds both.
##
## "required" and "optional" are the keys a legend line may carry besides
## id (always required) and the type itself.

const TYPES := {
	"pickup": {"required": ["upgrade"], "optional": ["value"]},
	"token": {"required": [], "optional": []},
	"health": {"required": [], "optional": []},
	"machine": {"required": [], "optional": ["upgrade", "value", "prize"]},
	"save": {"required": [], "optional": []},
	"platform": {"required": ["speed"], "optional": ["pause"]},
	"breakable": {"required": [], "optional": []},
	"emitter": {"required": ["speed", "every"], "optional": []},
	"spinner": {"required": ["period"], "optional": ["dir", "spikes"]},
}


## The kinds the player takes by touching them, and that a room can wait on.
const COLLECTIBLE: Array[String] = ["pickup", "token", "health"]


static func is_known(type: String) -> bool:
	return TYPES.has(type)


static func is_collectible(def: EntityDef) -> bool:
	return COLLECTIBLE.has(def.type)


## Whether the player works it by touching it: collectibles, 3TMs and save
## machines. A save machine is not collectible, so a room's `exits: pickups`
## never waits for it.
static func is_touchable(def: EntityDef) -> bool:
	return COLLECTIBLE.has(def.type) or def.type == "machine" or def.type == "save"


## The key in the player's flags that says a pickup or token was taken, or a
## save machine used.
static func flag_for(def: EntityDef) -> String:
	match def.type:
		"token":
			return Token.flag_for(def)
		"health":
			return HealthPip.flag_for(def)
		"save":
			return SaveMachine.flag_for(def)
	return Pickup.flag_for(def)


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
	if out.is_empty() and def.type == "machine":
		if def.props.has("upgrade") == def.props.has("prize"):
			out.append("machine %s needs exactly one of upgrade= and prize=" % def.id)
		elif def.props.has("prize") and (String(def.props["prize"]) != "health" or def.props.has("value")):
			out.append("machine %s: prize= can only be health, and takes no value=" % def.id)
	if out.is_empty() and (def.type == "pickup" or (def.type == "machine" and def.props.has("upgrade"))):
		var message := Upgrades.check(String(def.props["upgrade"]), String(def.props.get("value", "")))
		if not message.is_empty():
			out.append("%s %s: %s" % [def.type, def.id, message])
	if out.is_empty() and def.type == "emitter":
		var every := String(def.props["every"])
		if not every.is_valid_float() or every.to_float() <= 0.0:
			out.append("emitter %s: every= is seconds between platforms and has to be a number above 0, not \"%s\"" % [def.id, every])
	if out.is_empty() and def.type == "spinner":
		var period := String(def.props["period"])
		if not period.is_valid_float() or period.to_float() <= 0.0:
			out.append("spinner %s: period= is seconds for one turn and has to be a number above 0, not \"%s\"" % [def.id, period])
		var dir := String(def.props.get("dir", "ccw"))
		if dir != "ccw" and dir != "cw":
			out.append("spinner %s: dir= is ccw (the default) or cw, not \"%s\"" % [def.id, dir])
		for part in String(def.props.get("spikes", "")).split("+", false):
			if not SpinnerPath.SPIKE_NAMES.has(part):
				out.append("spinner %s: spikes= names parts of the bar joined by +, from %s, not \"%s\"" % [def.id, ", ".join(SpinnerPath.SPIKE_NAMES), part])
	if out.is_empty() and (def.type == "platform" or def.type == "emitter"):
		var speed := String(def.props["speed"])
		if not speed.is_valid_float() or speed.to_float() <= 0.0:
			out.append("platform %s: speed= is pixels a second and has to be a number above 0, not \"%s\"" % [def.id, speed])
		var pause := String(def.props.get("pause", "0"))
		if not pause.is_valid_float() or pause.to_float() < 0.0:
			out.append("platform %s: pause= is seconds at each end and has to be a number, 0 or more, not \"%s\"" % [def.id, pause])
	return out


## Whether the thing is in the world, given the player's flags. A pickup or a
## token is gone once it has been collected. This takes the flags, not GameState, so the
## parser and the tests can use the registry without the game running.
static func present(def: EntityDef, flags: Dictionary) -> bool:
	match def.type:
		"pickup":
			return not flags.has(Pickup.flag_for(def))
		"token":
			return not flags.has(Token.flag_for(def))
		"health":
			return not flags.has(HealthPip.flag_for(def))
	return true


## Builds the thing. `fills` is how many tokens each machine holds, by id.
static func create(def: EntityDef, fills := {}) -> Node2D:
	match def.type:
		"pickup":
			return Pickup.new(def)
		"token":
			return Token.new(def)
		"health":
			return HealthPip.new(def)
		"machine":
			return TokenMachine.new(def, int(fills.get(def.id, 0)))
		"save":
			return SaveMachine.new(def)
		"breakable":
			return BreakableWall.new(def)
	# A platform is built by the room from its path, not from its def.
	return null
