class_name EntityDef
extends RefCounted

## One thing a room file places with a legend glyph: what kind it is, its
## stable id, the cell it sits in, and the settings the legend gave it.

var glyph := ""
var type := ""
## Stable. It names this thing in the save, so it is written in the legend and
## never worked out from where the thing sits.
var id := ""
var cell := Vector2i.ZERO
## Every other key=value the legend line had, as text.
var props := {}
