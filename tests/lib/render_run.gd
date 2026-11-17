class_name RenderRun
extends RefCounted

## One run of tools/render.sh: parse, draw, save. The solver is reached only
## through the `solve` callable, and a preview never calls it, so a test can hand
## in a callable that records a call and fails.
##
## Exit codes: 0 drawn (a preview: the world loaded and was drawn, nothing more
## is claimed), 1 the world did not load, 2 bad arguments.

const OUT_DIR := "res://build/renders"


## `data` is a loaded WorldData. `solve` takes the data and returns a
## ReachGraph.Report; it is the only thing here that can start a solve. Returns the exit code.
static func run(data, args: PackedStringArray, out_dir: String, solve: Callable) -> int:
	var ids: Array = data.rooms.keys()
	ids.sort()
	var parsed := RenderArgs.parse(args, ids)
	if parsed.error != "":
		printerr("render: %s\n%s" % [parsed.error, RenderArgs.USAGE])
		return 2
	for message in data.errors:
		print("load problem: ", message)
	if parsed.preview and not data.errors.is_empty():
		print("PREVIEW NOT PRODUCED: the world did not load (%d problems above)" % data.errors.size())
		return 1
	var report: ReachGraph.Report = null
	if not parsed.preview and data.errors.is_empty():
		print("note: analysed render solves the world; a changed room can take a long time.")
		print("      For geometry only, run tools/render.sh --preview [ids].")
		report = solve.call(data)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var suffix := "_preview" if parsed.preview else ""
	var renderer := RoomRenderer.new()
	for id in ids:
		if parsed.ids.is_empty() or parsed.ids.has(String(id)):
			_save(renderer.room_image(data.rooms[id], report, parsed.preview), out_dir, "room_%s%s.png" % [id, suffix])
	if parsed.ids.is_empty():
		_save(renderer.world_image(data.rooms, parsed.preview), out_dir, "world%s.png" % suffix)
	if parsed.preview:
		print("preview: world loaded and geometry drawn. Reachability was NOT checked; run tools/validate.sh.")
	return 0 if data.errors.is_empty() else 1


static func _save(image: Image, out_dir: String, file_name: String) -> void:
	var path := ProjectSettings.globalize_path(out_dir + "/" + file_name)
	var error := image.save_png(path)
	print("wrote %s (%dx%d)" % [path if error == OK else "NOTHING, error %d for %s" % [error, path], image.get_width(), image.get_height()])
