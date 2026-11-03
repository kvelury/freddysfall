class_name EmitterKind
extends EntityKind


func type() -> String:
	return "emitter"


func required() -> Array[String]:
	return ["speed", "every"]


func structural() -> bool:
	return true


func problems(def: EntityDef) -> Array[String]:
	var out := PlatformKind._speed(def, "platform")
	var every := String(def.props.get("every", ""))
	if not every.is_valid_float() or every.to_float() <= 0.0:
		out.append("emitter %s: every= is seconds between platforms and has to be a number above 0, not \"%s\"" % [def.id, every])
	return out
