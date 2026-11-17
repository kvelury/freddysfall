class_name SimulationRequest
extends RefCounted

## One trajectory the solver asks MovementSim to run: where a body starts and
## what it presses, as plain data. It is what `ReachGraph.try_plan` used to take
## as twelve arguments. The ledge, the nearby solids and the room geometry it is
## run against belong to the SimulationBatch it is in, not to the request, so a
## batch loads them once.
##
## `to_dict` and `from_dict` are the versioned form at a process boundary. JSON
## cannot carry NAN or INF, so an optional value is explicit: `top` is null for
## "the ledge's own top", and `hang` is null for "not hanging". Numbers are never
## rounded: Godot's JSON text keeps only about 15 digits of a double (0.1 + 0.2
## comes back as 0.3), so a float is written as the 16 hex digits of its IEEE-754
## bits, which come back exactly. `identity` is stable content, not an instance id, a process id or a
## time, so two requests that differ in start tick, rider body, hang or any
## other input never share one.

## Bump when a field is added or its meaning changes.
const PROTOCOL := 1

var x := 0.0
var speed := 0.0
var input := 0.0
var hold := 0
var jump := false
## Ticks the path may run, or -1 for `ReachGraph.frame_limit`.
var limit := -1
## The tick the room's movers are at when the path starts, or -1 for no movers.
var tick := -1
## The height of what the body stands on, or NAN for the ledge's own top.
var top := NAN
## The mover body the body starts on, or -1.
var riding := -1
## A second press in the air at this tick after the start, held `air_hold`, or -1.
var air_frame := -1
var air_hold := 0
## Which of the batch's solid sets the body is tested against (`SimulationBatch.solid_sets`): 0 is the solids near the ledge, others are what a caller added with `add_solids` (the solids near a fall, say).
var solids := 0
## The wall a Tongue Climb hang is on, (+-1, 0), or (0, -1) for a ceiling; ZERO for none.
var hang := Vector2.ZERO


static func make(x_at: float, moving: float, steer: float, hold_ticks: int, jumps: bool, limit_ticks := -1, at_tick := -1, from_top := NAN, on_body := -1, in_air_frame := -1, in_air_hold := 0, hanging := Vector2.ZERO, solid_set := 0) -> SimulationRequest:
	var request := SimulationRequest.new()
	request.x = x_at
	request.speed = moving
	request.input = steer
	request.hold = hold_ticks
	request.jump = jumps
	request.limit = limit_ticks
	request.tick = at_tick
	request.top = from_top
	request.riding = on_body
	request.air_frame = in_air_frame
	request.air_hold = in_air_hold
	request.hang = hanging
	request.solids = solid_set
	return request


func to_dict() -> Dictionary:
	return {
		"protocol": PROTOCOL,
		"x": _encode(x), "speed": _encode(speed), "input": _encode(input), "hold": hold, "jump": jump,
		"limit": limit, "tick": tick, "solids": solids,
		"top": null if is_nan(top) else _encode(top),
		"riding": riding, "air_frame": air_frame, "air_hold": air_hold,
		"hang": null if hang == Vector2.ZERO else [_encode(hang.x), _encode(hang.y)],
	}


## The request `data` describes, or null if it is from another protocol, is
## missing a field, has one of the wrong type, or holds a number that is not finite.
static func from_dict(data: Dictionary) -> SimulationRequest:
	if int(data.get("protocol", -1)) != PROTOCOL:
		return null
	for name in ["x", "speed", "input", "hold", "jump", "limit", "tick", "solids", "riding", "air_frame", "air_hold"]:
		if not data.has(name):
			return null
	for name in ["x", "speed", "input"]:
		if is_nan(_decode(data[name])):
			return null
	for name in ["hold", "limit", "tick", "solids", "riding", "air_frame", "air_hold"]:
		if not (data[name] is int or (data[name] is float and is_finite(data[name]) and float(data[name]) == floorf(data[name]))):
			return null
	if not data["jump"] is bool or not data.has("top") or not data.has("hang"):
		return null
	var request := SimulationRequest.new()
	request.x = _decode(data["x"])
	request.speed = _decode(data["speed"])
	request.input = _decode(data["input"])
	request.hold = int(data["hold"])
	request.jump = data["jump"]
	request.limit = int(data["limit"])
	request.tick = int(data["tick"])
	request.solids = int(data["solids"])
	request.riding = int(data["riding"])
	request.air_frame = int(data["air_frame"])
	request.air_hold = int(data["air_hold"])
	if data["top"] != null:
		request.top = _decode(data["top"])
		if is_nan(request.top):
			return null
	if data["hang"] != null:
		var pair = data["hang"]
		if not pair is Array or pair.size() != 2:
			return null
		request.hang = Vector2(_decode(pair[0]), _decode(pair[1]))
		if is_nan(request.hang.x) or is_nan(request.hang.y):
			return null
	return request


## What the request is, as text: equal exactly when every field is.
func identity() -> String:
	return JSON.stringify(to_dict(), "", true)


## The 16 hex digits of a double's bits.
static func _encode(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


## The double `text` holds, or NAN if it is not 16 hex digits or is not finite.
static func _decode(text) -> float:
	if not text is String or text.length() != 16 or not text.is_valid_hex_number(false):
		return NAN
	var value: float = text.hex_decode().decode_double(0)
	return value if is_finite(value) else NAN
