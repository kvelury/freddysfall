class_name TestCase
extends SceneTree

## The base of every headless test. It prints `ok   label` or `FAIL label` for
## each check and counts the failures, so a test's last line (`NAME pass` or
## `NAME fail`) can never say pass after a check failed. It also has the
## watchdog every async test needs (a script error inside a coroutine would
## otherwise leave it waiting for good) and waits counted in physics ticks.
##
## tools/check.sh runs the tests with `--fixed-fps 60`: each frame is exactly
## 1/60 s of game time however long it takes, so timers, tweens and waits in
## ticks are the same on every machine and cost no real time. Measure time in
## ticks (`ticks`, `until`), never with Time.get_ticks_msec.

## Physics ticks in one second of game time.
const TICKS_PER_SECOND := 60

## How many checks have failed so far.
var failures := 0


## Prints the check and counts it if it failed. Returns `cond`, so a test can
## also fold the results together itself.
func check(cond: bool, label: String) -> bool:
	print(("ok   " if cond else "FAIL ") + label)
	if not cond:
		failures += 1
	return cond


## Whether every check so far passed.
func passed() -> bool:
	return failures == 0


## Fails the test if it is still running after `seconds` of game time.
func watchdog(seconds := 90.0) -> void:
	create_timer(seconds).timeout.connect(func() -> void:
		print("FAIL timed out")
		quit(1)
	)


## Waits `n` physics ticks.
func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Waits until `cond` is true, checking once a physics tick, for at most
## `max_ticks`. Returns how many ticks it took, or -1 if it never came true.
func until(cond: Callable, max_ticks: int) -> int:
	for i in max_ticks + 1:
		if cond.call():
			return i
		await physics_frame
	return -1


## Builds the world in `room` (its start, or the save if empty) the way the
## scene tests do: started directly, input scripted, added to the tree. `opts`
## may set "new_game" (bool) and "scripted" (bool, default true).
func boot_world(room := "", opts := {}) -> Node:
	var world: Node = load("res://src/world/world.tscn").instantiate()
	world.start_override = room
	world.new_game = bool(opts.get("new_game", false))
	root.add_child(world)
	await process_frame
	world.player.scripted = bool(opts.get("scripted", true))
	return world


## A user:// path that belongs to this test alone.
static func temp_user_path(name: String) -> String:
	return "user://test_%s" % name


## Prints the last line and quits: 0 if every check passed and `ok` holds.
func finish(name: String, ok := true) -> void:
	var good := ok and passed()
	print("%s %s" % [name, "pass" if good else "fail"])
	quit(0 if good else 1)
