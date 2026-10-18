class_name Tiles
extends RefCounted

## Every glyph a room file may use, and what each one means. The loader, the
## room builder, and the tests ask here instead of comparing string literals.
## Flags: solid, hazard, no_imprint, door, spawn. A missing flag is false.

const SOLID := "#"
const EMPTY := "."
const EXIT := "X"
const SPAWN := "P"
const NO_IMPRINT := "~"

const TABLE := {
	"#": {"solid": true},
	".": {},
	"X": {"door": true},
	"P": {"spawn": true},
	"~": {"no_imprint": true},
}


static func is_known(glyph: String) -> bool:
	return TABLE.has(glyph)


static func has_flag(glyph: String, flag: String) -> bool:
	var entry: Dictionary = TABLE.get(glyph, {})
	return bool(entry.get(flag, false))


## A cell the outer wall of a room may contain.
static func is_wall_glyph(glyph: String) -> bool:
	return has_flag(glyph, "solid") or has_flag(glyph, "door")
