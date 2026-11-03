class_name BreakableKind
extends EntityKind


func type() -> String:
	return "breakable"


func structural() -> bool:
	return true


func allowed_in_save_room() -> bool:
	return true


func create(def: EntityDef, _fills: Dictionary) -> Node2D:
	return BreakableWall.new(def)
