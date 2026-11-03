class_name HealthKind
extends EntityKind


func type() -> String:
	return "health"


func touchable() -> bool:
	return true


func collectible() -> bool:
	return true


func flag_for(def: EntityDef) -> String:
	return HealthPip.flag_for(def)


func create(def: EntityDef, _fills: Dictionary) -> Node2D:
	return HealthPip.new(def)
