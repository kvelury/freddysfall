class_name SpinnerKind
extends EntityKind


func type() -> String:
	return "spinner"


func required() -> Array[String]:
	return ["period"]


func optional() -> Array[String]:
	return ["dir", "spikes"]


func structural() -> bool:
	return true


func problems(def: EntityDef) -> Array[String]:
	var out: Array[String] = []
	var period := String(def.props.get("period", ""))
	if not period.is_valid_float() or period.to_float() <= 0.0:
		out.append("spinner %s: period= is seconds for one turn and has to be a number above 0, not \"%s\"" % [def.id, period])
	var dir := String(def.props.get("dir", "ccw"))
	if dir != "ccw" and dir != "cw":
		out.append("spinner %s: dir= is ccw (the default) or cw, not \"%s\"" % [def.id, dir])
	for part in String(def.props.get("spikes", "")).split("+", false):
		if not SpinnerPath.SPIKE_NAMES.has(part):
			out.append("spinner %s: spikes= names parts of the bar joined by +, from %s, not \"%s\"" % [def.id, ", ".join(SpinnerPath.SPIKE_NAMES), part])
	return out
