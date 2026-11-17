class_name RenderArgs
extends RefCounted

## What tools/render.sh was asked for: `--preview` and room ids. Anything else
## is an error, never passed through. Pure: no files, no world.

const USAGE := "usage: tools/render.sh [--preview] [room id ...]"

var preview := false
## The room ids asked for, in the order given; empty means every room (and the world map).
var ids: Array[String] = []
## Empty when the arguments were good; otherwise why not (the caller exits 2).
var error := ""


## `known` is every room id in the world.
static func parse(args: PackedStringArray, known: Array) -> RenderArgs:
	var parsed := RenderArgs.new()
	for arg in args:
		if arg == "--preview":
			parsed.preview = true
		elif arg.begins_with("-"):
			parsed.error = "unknown option %s" % arg
			return parsed
		elif known.has(arg):
			if not parsed.ids.has(arg):
				parsed.ids.append(arg)
		else:
			parsed.error = "unknown room id %s" % arg
			return parsed
	return parsed
