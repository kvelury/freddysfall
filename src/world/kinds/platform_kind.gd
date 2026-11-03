class_name PlatformKind
extends EntityKind


func type() -> String:
	return "platform"


func required() -> Array[String]:
	return ["speed"]


func optional() -> Array[String]:
	return ["pause"]


func structural() -> bool:
	return true


func allowed_in_save_room() -> bool:
	return true


func problems(def: EntityDef) -> Array[String]:
	return _speed(def, "platform")


static func _speed(def: EntityDef, label: String) -> Array[String]:
	var out: Array[String] = []
	var speed := String(def.props.get("speed", ""))
	if not speed.is_valid_float() or speed.to_float() <= 0.0:
		out.append("%s %s: speed= is pixels a second and has to be a number above 0, not \"%s\"" % [label, def.id, speed])
	var pause := String(def.props.get("pause", "0"))
	if not pause.is_valid_float() or pause.to_float() < 0.0:
		out.append("%s %s: pause= is seconds at each end and has to be a number, 0 or more, not \"%s\"" % [label, def.id, pause])
	return out
