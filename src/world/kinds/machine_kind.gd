class_name MachineKind
extends EntityKind


func type() -> String:
	return "machine"


func optional() -> Array[String]:
	return ["upgrade", "value", "prize"]


func touchable() -> bool:
	return true


func flag_for(_def: EntityDef) -> String:
	return ""


func present(_def: EntityDef, _flags: Dictionary) -> bool:
	return true


func create(def: EntityDef, fills: Dictionary) -> Node2D:
	return TokenMachine.new(def, int(fills.get(def.id, 0)))


func touch_rect(def: EntityDef) -> Rect2:
	return TokenMachine.touch_rect_for(def.cell)


func solver_effect(def: EntityDef, ledger: Dictionary) -> void:
	(ledger["machines"] as Array).append(def)


func problems(def: EntityDef) -> Array[String]:
	var out: Array[String] = []
	if def.props.has("upgrade") == def.props.has("prize"):
		out.append("machine %s needs exactly one of upgrade= and prize=" % def.id)
	elif def.props.has("prize") and (String(def.props["prize"]) != "health" or def.props.has("value")):
		out.append("machine %s: prize= can only be health, and takes no value=" % def.id)
	return out
