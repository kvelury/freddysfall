class_name PadLabels
extends RefCounted

## What a controller's buttons are called on its own face. The family comes
## from the name the system gives the pad: a PlayStation pad's face buttons are
## Cross, Circle, Square and Triangle (KeyCap draws those as small pictures),
## a Nintendo pad swaps A with B and X with Y, and anything else is read as an
## Xbox pad, which is also what Godot's button numbers follow.

const XBOX := "xbox"
const PLAYSTATION := "playstation"
const NINTENDO := "nintendo"

const _FACE := {
	XBOX: ["A", "B", "X", "Y"],
	PLAYSTATION: ["Cross", "Circle", "Square", "Triangle"],
	NINTENDO: ["B", "A", "Y", "X"],
}
const _SYSTEM := {XBOX: ["View", "Guide", "Menu"], PLAYSTATION: ["Share", "PS", "Options"], NINTENDO: ["-", "Home", "+"]}
const _SHOULDER := {XBOX: ["LB", "RB"], PLAYSTATION: ["L1", "R1"], NINTENDO: ["L", "R"]}
const _TRIGGER := {XBOX: ["LT", "RT"], PLAYSTATION: ["L2", "R2"], NINTENDO: ["ZL", "ZR"]}
const _DPAD := ["Up", "Down", "Left", "Right"]


## The family of the pad a system calls `joy_name`.
static func family(joy_name: String) -> String:
	var lower := joy_name.to_lower()
	for word in ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony"]:
		if lower.contains(word):
			return PLAYSTATION
	for word in ["nintendo", "switch", "joy-con", "pro controller"]:
		if lower.contains(word):
			return NINTENDO
	return XBOX


## The name of button `index` (a JoyButton) on a pad of `kind`.
static func button(kind: String, index: int) -> String:
	if index >= JOY_BUTTON_A and index <= JOY_BUTTON_Y:
		return _FACE[kind][index]
	match index:
		JOY_BUTTON_BACK: return _SYSTEM[kind][0]
		JOY_BUTTON_GUIDE: return _SYSTEM[kind][1]
		JOY_BUTTON_START: return _SYSTEM[kind][2]
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return _SHOULDER[kind][0]
		JOY_BUTTON_RIGHT_SHOULDER: return _SHOULDER[kind][1]
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			return _DPAD[index - JOY_BUTTON_DPAD_UP]
	return "Btn %d" % index


## The name of one direction of an axis (a JoyAxis): "LS Left", "RS Up", or a
## trigger.
static func axis(kind: String, axis_index: int, sign: int) -> String:
	match axis_index:
		JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X:
			return "%s %s" % [stick(axis_index), "Left" if sign < 0 else "Right"]
		JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_Y:
			return "%s %s" % [stick(axis_index), "Up" if sign < 0 else "Down"]
		JOY_AXIS_TRIGGER_LEFT:
			return _TRIGGER[kind][0]
		JOY_AXIS_TRIGGER_RIGHT:
			return _TRIGGER[kind][1]
	return "Axis %d" % axis_index


## "LS" or "RS" for a stick axis.
static func stick(axis_index: int) -> String:
	return "LS" if axis_index == JOY_AXIS_LEFT_X or axis_index == JOY_AXIS_LEFT_Y else "RS"
