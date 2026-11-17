extends SceneTree

## Draws rooms as PNGs in build/renders/, one per room plus world.png, so a
## drawing and its translation can be compared by eye. tools/render.sh runs this.
##
## tools/render.sh [--preview] [ids]: room ids draw only those rooms.
## `--preview` draws geometry without loading the solver or its cache, as
## room_<id>_preview.png and world_preview.png with a label saying
## reachability was not checked. Without it the world is solved first (the
## committed cache is read, not written) and the findings are marked.
##
## Colours: white solid, green door, cyan player start, purple spikes, gold a pickup, orange a door that was
## sealed because nothing is on the far side, grey dots a no-imprint cell,
## magenta a glyph the loader does not know, a checker over a door in a room
## that holds its doors shut until a rule is met, a gold box round a 3TM's 3 x 3 cells, light blue a moving platform
## where it starts and blue dots its track. Red bar on a ledge nobody can
## reach, yellow bar on a ledge you cannot get back from, grey bar on one that a
## room marked `trap: allowed` leaves one-way, red box on a door
## nobody can reach (analysed renders only). Faint lines every 5 cells, bright lines between screens.
## The drawing is in tests/lib/room_renderer.gd, the run in tests/lib/render_run.gd.


func _initialize() -> void:
	var data = preload("res://src/autoload/world_data.gd").new()
	data.ensure_loaded()
	quit(RenderRun.run(data, OS.get_cmdline_user_args(), RenderRun.OUT_DIR, _solve))


func _solve(data) -> ReachGraph.Report:
	var cfg := load("res://src/player/movement.tres") as MovementConfig
	var graph := ReachGraph.new(data.rooms, cfg)
	# The committed solver cache, as validate.sh reads it: only rooms that
	# changed are solved. It is not written back here.
	graph.cache = SolverCache.new("res://data/solver-cache")
	return graph.solve(data.start_room)
