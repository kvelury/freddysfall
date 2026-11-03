class_name Entities
extends RefCounted

## The kinds of thing a room legend can place. Each kind is an EntityKind.
## Adding one is a subclass and a line in `_ensure`. The parser asks here
## whether a legend line is valid, and the room asks here to build the thing.
## A moving platform and a breakable wall are drawn as more than one cell:
## the room parser turns a platform into a PlatformPath, and a breakable wall's
## cells go to RoomInfo.breakables; the room builds both.
##
## "required" and "optional" are the keys a legend line may carry besides
## id (always required) and the type itself.

static var _by_type := {}
static var _types := {}


static func kind(type: String) -> EntityKind:
	_ensure()
	return _by_type.get(type) as EntityKind


static func _ensure() -> void:
	if not _by_type.is_empty():
		return
	var made_list: Array[EntityKind] = [
		PickupKind.new(), TokenKind.new(), HealthKind.new(), MachineKind.new(), SaveKind.new(),
		PlatformKind.new(), EmitterKind.new(), SpinnerKind.new(), BreakableKind.new(),
	]
	for made in made_list:
		_by_type[made.type()] = made
		_types[made.type()] = {"required": made.required(), "optional": made.optional()}


static func is_known(type: String) -> bool:
	_ensure()
	return _by_type.has(type)


static func is_collectible(def: EntityDef) -> bool:
	var made := kind(def.type)
	return made != null and made.collectible()


## Whether the player works it by touching it: collectibles, 3TMs and save
## machines. A save machine is not collectible, so a room's `exits: pickups`
## never waits for it.
static func is_touchable(def: EntityDef) -> bool:
	var made := kind(def.type)
	return made != null and made.touchable()


## The key in the player's flags that says a pickup or token was taken, or a
## save machine used.
static func flag_for(def: EntityDef) -> String:
	var made := kind(def.type)
	return "" if made == null else made.flag_for(def)


## What is wrong with a legend line's settings, as sentences. `def` has its
## type, id and props filled in.
static func problems(def: EntityDef) -> Array[String]:
	var out: Array[String] = []
	if not is_known(def.type):
		out.append("\"%s\" is not a kind of thing a legend can place (kinds: %s)" % [def.type, ", ".join(_types.keys())])
		return out
	if def.id.is_empty():
		out.append("%s needs an id=, a name that stays the same for good" % def.type)
	var spec: Dictionary = _types[def.type]
	for key in spec["required"]:
		if not def.props.has(key):
			out.append("%s %s needs %s=" % [def.type, def.id, key])
	for key in def.props:
		if not spec["required"].has(key) and not spec["optional"].has(key):
			out.append("%s %s has %s=, which %s does not use" % [def.type, def.id, key, def.type])
	if out.is_empty():
		out.append_array(kind(def.type).problems(def))
	if out.is_empty() and (def.type == "pickup" or (def.type == "machine" and def.props.has("upgrade"))):
		var message := Upgrades.check(String(def.props["upgrade"]), String(def.props.get("value", "")))
		if not message.is_empty():
			out.append("%s %s: %s" % [def.type, def.id, message])
	return out


## Whether the thing is in the world, given the player's flags. A pickup or a
## token is gone once it has been collected. This takes the flags, not GameState, so the
## parser and the tests can use the registry without the game running.
static func present(def: EntityDef, flags: Dictionary) -> bool:
	var made := kind(def.type)
	return made == null or made.present(def, flags)


## Builds the thing. `fills` is how many tokens each machine holds, by id.
## A platform, emitter or spinner is built by the room from its path, so this
## returns null for those.
static func create(def: EntityDef, fills := {}) -> Node2D:
	var made := kind(def.type)
	return null if made == null else made.create(def, fills)
