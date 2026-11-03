class_name PickupKind
extends EntityKind


func type() -> String:
	return "pickup"


func required() -> Array[String]:
	return ["upgrade"]


func optional() -> Array[String]:
	return ["value"]


func touchable() -> bool:
	return true


func collectible() -> bool:
	return true


func flag_for(def: EntityDef) -> String:
	return Pickup.flag_for(def)


func create(def: EntityDef, _fills: Dictionary) -> Node2D:
	return Pickup.new(def)


func solver_effect(def: EntityDef, ledger: Dictionary) -> void:
	(ledger["abilities"] as Abilities).apply(Upgrades.get_def(String(def.props["upgrade"])), Upgrades.parse_value(String(def.props["upgrade"]), String(def.props.get("value", ""))))
