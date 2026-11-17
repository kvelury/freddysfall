extends TestCase

## tools/render.sh: its arguments, and that a preview never reaches the solver,
## never touches the committed cache, says it is a preview, and draws the same
## geometry as an analysed render. Uses a folder of its own for the images.

const OUT := "user://render_test"
const POCKET := "res://tests/fixtures/worlds/pocket/"
const CACHE := "res://data/solver-cache"

var _solves := 0


func _initialize() -> void:
	var ok := _arguments()
	ok = _preview_run() and ok
	ok = _analysed_run() and ok
	ok = _images() and ok
	ok = _failed_load() and ok
	_clear()
	finish("RENDER", ok)


func _world():
	var data = preload("res://src/autoload/world_data.gd").new()
	data.load_from(POCKET + "world.json", POCKET + "rooms/")
	return data


func _solve(_data) -> ReachGraph.Report:
	_solves += 1
	return null


func _clear() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + file)


func _files() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var names := Array(DirAccess.get_files_at(ProjectSettings.globalize_path(OUT)))
	names.sort()
	return names


func _arguments() -> bool:
	var known := ["1", "2", "s1"]
	var ok := true
	var plain := RenderArgs.parse(PackedStringArray([]), known)
	ok = check(plain.error == "" and not plain.preview and plain.ids.is_empty(), "no arguments: everything, analysed") and ok
	var some := RenderArgs.parse(PackedStringArray(["--preview", "s1", "2", "s1"]), known)
	ok = check(some.error == "" and some.preview and some.ids == ["s1", "2"], "a preview of some rooms, in the order named, once each") and ok
	ok = check(RenderArgs.parse(PackedStringArray(["--previw"]), known).error != "", "an unknown flag is an error") and ok
	ok = check(RenderArgs.parse(PackedStringArray(["--jobs", "4"]), known).error != "", "a flag meant for another tool is an error") and ok
	ok = check(RenderArgs.parse(PackedStringArray(["99"]), known).error != "", "an unknown room id is an error") and ok
	ok = check(RenderArgs.parse(PackedStringArray(["--preview", "1", "99"]), known).error != "", "one unknown id spoils the run") and ok
	return ok


func _cache_state() -> Dictionary:
	var state := {}
	for file in DirAccess.get_files_at(CACHE):
		var path := CACHE + "/" + file
		state[file] = [FileAccess.get_sha256(path), FileAccess.get_modified_time(path)]
	return state


func _preview_run() -> bool:
	_clear()
	var before := _cache_state()
	_solves = 0
	var code := RenderRun.run(_world(), PackedStringArray(["--preview"]), OUT, _solve)
	var ok := check(code == 0, "a preview of a good world exits 0")
	ok = check(_solves == 0, "a preview never solves") and ok
	ok = check(_cache_state() == before, "a preview leaves every committed cache file's bytes and mtime alone") and ok
	var names := _files()
	ok = check(names.has("world_preview.png") and names.has("room_1_preview.png"), "it writes *_preview.png files %s" % [names]) and ok
	ok = check(not names.has("world.png") and not names.has("room_1.png"), "and none of the analysed names") and ok
	_clear()
	code = RenderRun.run(_world(), PackedStringArray(["--preview", "1"]), OUT, _solve)
	ok = check(code == 0 and _files() == ["room_1_preview.png"], "named rooms only, and no world map %s" % [_files()]) and ok
	return ok


func _analysed_run() -> bool:
	_clear()
	_solves = 0
	var code := RenderRun.run(_world(), PackedStringArray(["1"]), OUT, _solve)
	var ok := check(code == 0 and _solves == 1, "an analysed render solves once")
	ok = check(_files() == ["room_1.png"], "and writes the analysed name") and ok
	_solves = 0
	code = RenderRun.run(_world(), PackedStringArray(["--nope"]), OUT, _solve)
	ok = check(code == 2 and _solves == 0, "bad arguments exit 2 before anything is solved") and ok
	return ok


func _images() -> bool:
	var data = _world()
	var renderer := RoomRenderer.new()
	var info: RoomInfo = data.rooms["1"]
	var plain := renderer.room_image(info, null)
	var preview := renderer.room_image(info, null, true)
	var ok := check(plain.get_size() == preview.get_size(), "a preview room image is the same size")
	var clear := RoomRenderer.PREVIEW_CLEAR
	var same := plain.get_region(Rect2i(0, clear, plain.get_width(), plain.get_height() - clear)).get_data() == preview.get_region(Rect2i(0, clear, plain.get_width(), plain.get_height() - clear)).get_data()
	ok = check(same, "below the header it is the geometry-only drawing, pixel for pixel") and ok
	ok = check(plain.get_data() != preview.get_data(), "and the header carries the strip") and ok
	var missing := []
	for glyph in RoomRenderer.PREVIEW_LABEL:
		if glyph != " " and not RoomRenderer.PREVIEW_FONT.has(glyph):
			missing.append(glyph)
	ok = check(missing.is_empty(), "the font has every letter of the label %s" % [missing]) and ok
	var world := renderer.world_image(data.rooms)
	var world_preview := renderer.world_image(data.rooms, true)
	ok = check(world_preview.get_height() > world.get_height() and world_preview.get_width() >= world.get_width(), "the world preview has a band for the strip") and ok
	return ok


func _failed_load() -> bool:
	_clear()
	var data = _world()
	data.errors.append("a made-up loader problem")
	_solves = 0
	var code := RenderRun.run(data, PackedStringArray(["--preview"]), OUT, _solve)
	var ok := check(code == 1 and _solves == 0, "a preview of a world that did not load exits 1")
	ok = check(_files().is_empty(), "and writes no preview, so none can be mistaken for a pass") and ok
	return ok
