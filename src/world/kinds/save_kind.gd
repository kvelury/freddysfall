class_name SaveKind
extends EntityKind


func type() -> String:
	return "save"


func touchable() -> bool:
	return true


func allowed_in_save_room() -> bool:
	return true


func flag_for(def: EntityDef) -> String:
	return SaveMachine.flag_for(def)


func present(_def: EntityDef, _flags: Dictionary) -> bool:
	return true


func create(def: EntityDef, _fills: Dictionary) -> Node2D:
	return SaveMachine.new(def)


func touch_rect(def: EntityDef) -> Rect2:
	return SaveMachine.touch_rect_for(def.cell)
