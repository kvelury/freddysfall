class_name SpinnerKind
extends EntityKind


func type() -> String:
	return "spinner"


func required() -> Array[String]:
	return ["period"]


func optional() -> Array[String]:
	return ["dir", "spikes", "pivot", "breakable"]


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
	if def.props.has("pivot") and SpinnerKind.pivot_of(def) == Vector2.INF:
		out.append("spinner %s: pivot= is the point it turns about, in cells from the room's top left as x,y (16,10 is the corner shared by four cells), not \"%s\"" % [def.id, def.props["pivot"]])
	if def.props.has("breakable") and String(def.props["breakable"]) != "true":
		out.append("spinner %s: breakable= is true (leave it out for a spinner the tongue cannot break), not \"%s\"" % [def.id, def.props["breakable"]])
	return out


## The point a spinner turns about, in room pixels, from `pivot=x,y` (cells), or
## `Vector2.INF` when there is none or it is not two numbers.
static func pivot_of(def: EntityDef) -> Vector2:
	if not def.props.has("pivot"):
		return Vector2.INF
	var parts := String(def.props["pivot"]).split(",")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return Vector2.INF
	return Vector2(parts[0].to_float(), parts[1].to_float()) * float(Grid.CELL)
