# Freddy's Fall

A browser-playable pixel metroidvania in Godot 4.7 and GDScript. The world is a set of ASCII room files, and Imprint (the mouse cursor becomes a temporary platform) is the first ability.

This file is the project: how it is laid out, how the code fits together, the rules the code keeps, how to run and check it, and how to change it without breaking those rules. What the game is, and why each rule exists, is in [docs/design/game-design.md](docs/design/game-design.md). How an agent works here, including turning a drawing into a room, is in [AGENTS.md](AGENTS.md) (`CLAUDE.md` points at it).

**Reading order for someone about to change the code:** this file, then the design doc's "Implementation reference" and "Decision log", then the code you are changing and its test. `docs/plans/foundation.md` is the history of how the project was set up, and `docs/plans/soft-duotone-palettes.md` is a plan for work not built yet. Neither is the current record.

## Requirements

[Godot 4.7](https://godotengine.org/) with the web export templates installed. Python 3 serves the exported page. Everything is run from the repo root.

`project.godot` asks for feature `4.7` and the GL Compatibility renderer.

## Run

Open the project in the editor and press Play. The main scene is `res://src/world/world.tscn`.

- **Start in a room:** `godot --path . -- --room=3`, or `?room=3` on the web, or F4, a room number and Enter in a debug build. A game started in a chosen room neither reads nor writes the save.
- **Saving:** the game saves by itself when a room is entered, when a pickup or token is taken, when a 3TM finishes, when a save machine is used, and when the map is closed after its zoom changed. Whatever the player has done is kept, but a reload always starts at the save: the machine of the save room they last entered, or the start room's `P` before that. The file is `user://save.json` (the browser's IndexedDB on the web). A plain reload keeps the game.
- **Start over:** `--new-game`, or `?new-game=1` on the web. It deletes the save and empties the game's state before anything is placed, so even a reload before the first autosave cannot bring the old game back. While `?new-game=1` stays in the address, every reload is a new game.
- **Keys:** `move_left`, `move_right` (A/D, arrows), `jump` (Space, W, Up), `move_down` (S, Down; reserved, does nothing), `imprint` (left mouse button), `map` (hold Tab or M), `map_zoom_in` (Up or W while the map is held), `map_zoom_out` (Down or S), `debug` (F3). F4 is handled by the debug overlay directly. The table with what each does is in the design doc.

## Web

The Web preset in `export_presets.cfg` turns thread support off, so the page does not need cross-origin isolation headers. A static server is enough.

Room files are plain text. The preset's `include_filter` is `*.txt` so those files are packed into the export. Without that, `res://data/rooms/` is missing from the web build.

```sh
./tools/build_web.sh
./tools/serve.sh
```

`build_web.sh` imports the project, exports a release build to `build/web/index.html`, injects a listener that keeps Tab from leaving the canvas, and gives the `.pck` and `.wasm` a name that changes with the pack's hash (symlinks, `g<hash>.pck`) so a browser cannot play a cached old pack as the new game. `serve.sh` serves that directory at http://localhost:8060 and tries `open`. `build/` is gitignored.

## Checking your work

Run `tools/check.sh` before opening a pull request. It imports the project, runs all 17 headless tests, validates the whole world without the solver cache, builds the release web export, and checks that the room data and cache-tagged browser files are present. CI runs the same command. After it passes, serve that build and play the affected route yourself; the automated checks do not judge movement feel, room readability or visual feedback.

```sh
tools/check.sh                 # the complete automated gate and a fresh web build
tools/serve.sh                 # serve that build at http://localhost:8060 for the playthrough
tools/validate.sh              # the whole world, solved: a room is not done until this exits 0
tools/validate.sh --no-cache   # the same, without the solver's cache
tools/render.sh [ids]          # PNGs of rooms and the world map in build/renders/
tools/snap.sh <id>             # a real in-game frame of a room (opens a window; run on your own machine)
godot --headless --path . --script tests/<name>.gd
```

After adding a script with a `class_name`, run `godot --headless --path . --import` once. A headless script cannot see the new class until then (`validate.sh` and `render.sh` do it for you).

| Script | What it drives |
| --- | --- |
| `tests/reach_test.gd` | `MovementSim` against the room rectangles, the world's room shapes and door links, door crossing, the camera clamp, the loader's every error (built from strings), and the solver on small worlds built to be wrong in one way each. Includes the check that room 3's level entrance cannot bypass the staircase to its token. Prints `RESULT pass`. |
| `tests/physics_test.gd` | The player scene through room s1, jump by jump (past its save machine, which holds the door shut), and out its door. Prints `PHYSICS pass`. |
| `tests/parity_test.gd` | Replays input plans through the player and through the solver's simulator. They must end within 0.01 px. Prints `PARITY pass`. |
| `tests/door_test.gd` | The player walks level through the aligned door from room 2 onto room 3's entrance ledge, and goes back. Prints `DOOR pass`. |
| `tests/shaft_test.gd` | The player drops down the hole in room 3 into room 4 and climbs back up, keeping speed through the doors. Prints `SHAFT pass`. |
| `tests/hazard_test.gd` | In room 5, spikes and falling out of a room shatter the player and, with health, put them back on safe floor (it gives the player health, since with none a death goes to the save room). An Imprint over spikes that breaks under the player does not leave a respawn in the air, and a bad respawn spot is stepped back from. Prints `HAZARD pass`. |
| `tests/start_test.gd` | Starting in a chosen room, an unknown room, `warp_to`, and the F4 warp (digits, and `s` for a save room). Prints `START pass`. |
| `tests/entity_test.gd` | The room header: the legend, the `exits:` rule and `trap:`, tokens, 3TMs, save machines and save rooms (ids included). A valid one loads, and each way of writing one wrong is an error with its line. Prints `ENTITY pass`. |
| `tests/save_test.gd` | `Abilities`, `GameState`, and the save file: round trip, tokens, machines, the save room, health and the map's zoom, damaged, newer, older (a version 2 file is carried over) and missing-room files, and `erase` doing nothing while saving is off. Uses its own file. Prints `SAVE pass`. |
| `tests/map_test.gd` | The map's three zoom levels (what each shows, that Out always fits the whole map), the legend, the keys (Up/W, Down/S), that the map and the marker agree at every level, that Up on the map does not jump the player, and that the level is saved while a new game wipes the save and a reload keeps it. Prints `MAP pass`. |
| `tests/cache_test.gd` | The solver's cache on disk: a run that reads it says exactly what a run without it says, and a room is only taken from it while the room, its doors' neighbours and the solver are unchanged. Damaged files are ignored. Prints `CACHE pass`. |
| `tests/token_test.gd` | Room 2's doors are blocked until its token is taken, the blocks stop the player and then open, tokens show on the body, a full pocket leaves the next token, and a game resumed from the save has the token spent. Prints `TOKEN pass`. |
| `tests/save_room_test.gd` | Room s1: its door is blocked until the player walks into the save machine, they are held about a second while it lights, a line says "Game saved", the door opens and the save file resumes at the machine. Dying with no health goes to the machine without another pause, dying with a pip stays on safe floor, and dying before any save room was entered goes to the start. Prints `SAVEROOM pass`. |
| `tests/machine_test.gd` | The 3TM in room 4: how full it is, tokens flying in one at a time, the third giving Imprint, a spent machine doing nothing, and a save keeping its fill. Prints `MACHINE pass`. |
| `tests/imprint_test.gd` | Where an Imprint platform may go (every refusal), whether the player can land on one, the blink, and the countdown lines. Prints `IMPRINT pass`. |
| `tests/imprint_play_test.gd` | Imprint in room 5: locked until found, placed by the action, solid under the player, replaced, broken by time, cleared on leaving a room and on dying. Prints `IMPRINTPLAY pass`. |
| `tests/imprint_solver_test.gd` | The solver with Imprint, on strings: a pit too wide to jump is shut without Imprint and open with it, a platform that breaks too soon is no use, `~` cells forbid it, a room reports the pickup it needs, a room that holds its doors shut waits for its token, three tokens and a 3TM give Imprint, a `trap: allowed` room is a warning and not an error, a fall four screens tall lands, and room 6's wall needs Imprint. Prints `IMPRINTSOLVER pass`. |
| `tests/validate.gd` | Loads the whole world, then solves it: every room and door reachable from the start, nowhere to get stuck. Lists every problem and exits 1 if there is one, and says where the time went. Keeps what it works out about each room in `build/solver-cache/` (`--no-cache` skips it). Run through `tools/validate.sh`. |
| `tests/render.gd` | Draws each room and the world map as PNGs in `build/renders/`, marking unreachable ledges, traps, one-way ledges, sealed doors, blocked doors, and 3TMs. Run through `tools/render.sh`. |

Two kinds of test, and which to write:

- **Pure tests** build rooms or worlds from strings (`RoomParser.build`, `ReachGraph.new`) and never instance the world. They are fast and exact. Use them for rules, the solver, and anything with no scene.
- **Scene tests** instance `world.tscn` and set `Player.scripted` so input comes from the test and not the keyboard. Use them for things only the running game does (doors, the 3TM, saving, the map overlay).

## Code layout

| Path | Role |
| --- | --- |
| `project.godot` | Application `Freddysfall` 0.1.0, autoloads (`GameState`, `Save`, `WorldData`), display (320×180, integer scale, nearest filter), input actions, 60 Hz physics with interpolation. |
| `data/world.json` | Start room, and each room's id and `grid_pos`. The room's file is `data/rooms/<id>.txt`. |
| `data/rooms/` | One ASCII file per room: an optional header, then the grid. |
| `data/upgrades.json` | The upgrades a pickup or 3TM can give: a name, the ability stat it changes, a kind (`unlock`, `max`, `add`) and an optional message. |
| `src/core/` | `Grid` (cell and screen sizes, the camera clamp), `Abilities` (what the player can do), `Upgrades` (reads `upgrades.json`). No scene, no autoload. |
| `src/autoload/` | `WorldData` (reads the world files, keeps the rooms and `errors`), `GameState` (current room, visited set, abilities, flags, tokens, machines, map zoom, save room, health), `Save` (reads and writes `user://save.json`). |
| `src/world/room_parser.gd` | Pure text-to-`RoomInfo`: header, glyphs and walls, legend, merging `#` into rectangles, pairing and sealing doors. |
| `src/world/room_info.gd`, `door.gd`, `entity_def.gd`, `tiles.gd` | A loaded room, one opening in its wall (and `Door.crossing`, where a body appears on the far side), one legend entry, and the glyph table. |
| `src/world/entities.gd`, `entities/` | The kinds of thing a legend can place (`pickup`, `token`, `machine`, `save`): the registry and one script each. |
| `src/world/exit_rules.gd` | The conditions a room can put on leaving it. |
| `src/world/world.gd`, `world.tscn` | The scene root: places the player, builds rooms, door slides, death and respawn, collecting, the 3TM feed, autosave. |
| `src/world/room.gd` | One room as a node: solids drawn in a chunk per screen, hazards, doors (halos or blocks), the things in it. |
| `src/world/exit_halo.gd`, `shatter.gd`, `flying_token.gd` | Effects: the glow in a doorway, a burst of shards, a token flying into a 3TM. |
| `src/world/reach_graph.gd` | The solver: ledges, the jumps and drops between them, doors, exit rules, what each room needs, traps. Used by `validate.sh` and the tests, never by the running game. |
| `src/world/imprint_search.gd` | The part of the solver that puts Imprint platforms down. |
| `src/world/solver_cache.gd` | The solver's results kept on disk between runs. |
| `src/imprint/` | `ImprintTool` (the cursor, placing, ageing, drawing), `ImprintPlatform` (one platform and its clock), `ImprintRules` (where one may go), `ImprintReach` (whether the player can land on one from where they are). |
| `src/player/` | `MovementConfig` (`movement.tres`), `MovementSim` (all of the movement), `Player` (a `Node2D` that advances a `MovementSim.State`), `InventoryMarks` (tokens and the Imprint line cut into the body). |
| `src/ui/` | `MapOverlay` (the map, drawn into its own viewport) and `MapView` (its zoom and legend maths), `Toast` (a line of text), `DebugOverlay` (F3, F4, and load errors). |
| `tests/` | The tests above. |
| `tools/` | `check.sh` (the complete automated gate), `validate.sh`, `render.sh`, `snap.sh`, `build_web.sh`, `serve.sh`. |
| `AGENTS.md`, `CLAUDE.md` | How an agent works here. |
| `docs/design/game-design.md` | The design record: what the game is, the rules, how each system is built, and why. |
| `docs/testing-checklist.md` | What nobody has played yet. Mark things played here, and keep it short. |
| `docs/plans/` | History and plans, not the current record. |

## How the code fits together

### Data flow

```
data/world.json + data/rooms/*.txt
   │  WorldData.ensure_loaded()  ──  RoomParser.build()  (pure; collects every error)
   ▼
RoomInfo / Door / EntityDef  (plain data, no nodes)
   │                                   │
   │ World builds a Room node          │ ReachGraph reads the same RoomInfo
   ▼                                   ▼
Room (drawn chunks, doors,        ledges → jumps → doors → rooms → "what does each room need"
things)  ◄── Player advances a    ◄── MovementSim.step / simulate_jump  ──►  ImprintReach, ImprintSearch
MovementSim.State each tick           (one implementation of the movement, shared)

GameState (autoload) ◄──► Save (autoload, user://save.json)
```

### Boot

1. `WorldData._ready` loads `world.json`, reads each room's file, and calls `RoomParser.build`. Every problem is appended to `WorldData.errors` (never stops at the first) and pushed as an error. A debug build lists them on screen.
2. `World._ready` picks the start: `--room=`/`?room=` (no save), else `--new-game`/`?new-game=1` (erase the save, reset the state, start room), else the save, else the start room. It then `_place_in`s the player.
3. `_place_in` frees the old room, builds the new `Room` from `RoomInfo` and `GameState` (flags and machine fills decide what is still in the world), puts the player on it, and calls `GameState.visit`.

### Each physics tick (`World._physics_process`)

In this order, skipped while the world is busy (a door slide, a death, a 3TM feed): die if touching a hazard or outside the room by more than 60 px; otherwise collect what the player touches, and then change rooms if a door is touched, else remember safe floor. The camera follows last. `Player._physics_process` runs `MovementSim.step`; `ImprintTool._physics_process` ages platforms (not while busy) and refreshes the preview.

### What the code keeps true

These are the rules a change must not break. The design doc says why each exists.

1. **One implementation of the movement.** The player, the solver, `ImprintReach` and `ImprintSearch` all advance bodies with `MovementSim.step`/`simulate_jump`. Never copy a formula. `parity_test` holds the player and the simulator to 0.01 px.
2. **Room data is parsed purely.** `RoomParser` and everything that reads `RoomInfo` take plain values, not autoloads or nodes, so a test can build a world from strings. Rules that depend on player state take the state as an argument (`ExitRules.met(info, flags)`, `Entities.present(def, flags)`), not `GameState`.
3. **Errors are collected, not thrown.** Loading reports every problem as a sentence with the room (and line, for the header) and keeps going. Repeats are capped (`MAX_PER_KIND`) and counted.
4. **Ids are stable and global.** A pickup, token, 3TM or save machine is named by an `id` written in the room's legend, never derived from where it sits, because the save remembers it by that id. Unique across the whole world. Never rename one.
5. **Everything is on the 10 px grid and whole pixels.** Rooms are whole screens (32×18 cells). Drawing and the camera use whole pixels at integer scale; the map is redrawn at each zoom, not stretched.
6. **Nodes that move in `_process` turn physics interpolation off.** With 60 Hz physics and interpolation on, a node moved between physics steps glides from its old transform. The player is interpolated on purpose; the camera, effects, the door blocks, the map layer and the Imprint tool are not. A `Camera2D` inside the map's viewport lagged one zoom step behind for exactly this reason, so that layer is moved directly.
7. **The save has a version.** The file's shape changes only with `Save.VERSION` and a step in `Save._migrate`; an unreadable or newer file is set aside as `save.json.bad`, never overwritten. Anything missing in a save falls back to its starting value.
8. **Behaviour changes update the design doc in the same pull request.**
9. **The solver's cache is only as good as its fingerprint.** Anything that can change what a jump does must be in `SolverCache.SOLVER_FILES`, and the room fingerprint must cover everything about a room the solver reads. `cache_test` checks the list's files exist and that they are listed.

### Standards

What the existing code does, so new code reads the same:

- **Typed GDScript, tabs.** Declare types (`var x := ...`, typed arrays and parameters, `->` return types). Names: `snake_case` functions and variables, `PascalCase` classes, `UPPER_SNAKE` constants, a leading `_` for anything private. A named constant for any number that carries meaning (`SAFE_SPACING`, `TRANSITION_TIME`), with a line saying what it is.
- **`##` comments say what and why, in plain words,** on every class, public function, constant and field that is not obvious. They describe the behaviour, not the history. Match the density of the file you are in.
- **Put logic where a test can reach it.** Pure rules go in `RefCounted` classes with `static` functions and no autoload references (`MovementSim`, `MapView`, `ExitRules`, `ImprintRules`, `RoomParser`, `SolverCache`). Scene scripts stay thin. A test script cannot name an autoload at compile time, so it uses `root.get_node(...)` and an untyped `Node`.
- **Registries, not scattered cases.** Glyphs live in `Tiles.TABLE`, legend kinds in `Entities.TYPES`, exit rules in `ExitRules.RULES`, upgrades in `data/upgrades.json`. Add to the registry, then to its one `match`.
- **Tests print `ok   label` / `FAIL label` through a `_check(cond, label)` helper and one final `NAME pass|fail` line,** and exit 0 or 1. An async test sets a 90 second watchdog timer so a script error inside a coroutine cannot hang it. Tests that write files use their own paths and clean up; none touches the player's save or the real solver cache.
- **Every new test is mutation-checked.** Break the thing it guards on purpose (flip a comparison, drop a field, remove a line), run the test, see it fail, put it back. A test that cannot fail guards nothing. Pull requests say which mutants were tried.
- **Words in the UI and docs are plain.** Short sentences, no jargon, say what the thing does for the player. Numbers in the docs are the real numbers.
- **Report every judgement.** Translating a drawing, nudging a platform, choosing a number: say what was rounded and why (see `AGENTS.md`).

### Recipes

- **A new room.** Add `data/rooms/<id>.txt` and its entry in `data/world.json`; follow `AGENTS.md`; run `tools/validate.sh` and `tools/render.sh <id>`; add a test only if the room has behaviour of its own.
- **A new glyph.** One line in `Tiles.TABLE` with its flags; then whatever reads that flag (`RoomInfo`, `RoomParser`, `Room`, the renderer, the solver). The glyph table in `AGENTS.md` and the design doc.
- **A new legend kind** (like `token`). A line in `Entities.TYPES` (required and optional keys), a script under `src/world/entities/`, a case in `Entities.create` and `Entities.present`, `is_collectible`/`is_touchable` if the player takes or works it, a case in `World._collect`, the solver's `_things_of` and `Geometry.things`, `render.gd`, and `entity_test`.
- **A new exit rule.** A line in `ExitRules.RULES` and a case in `ExitRules.met` (taking flags, never `GameState`), and `problem` if some rooms cannot use it.
- **A new upgrade.** An entry in `data/upgrades.json`; if it needs a new stat, a field in `Abilities` and its name in `Abilities.STATS`, `to_dict` and `from_dict`; then whatever uses it. If the solver cares (width, duration), it is part of `ImprintSearch`'s keys.
- **A change to the save.** Add the field to `GameState.to_dict`/`load_dict` with a default; bump `Save.VERSION` only if old files cannot be read as they are, and add the step to `_migrate`.
- **A change to anything the solver reads.** The cache invalidates itself (the fingerprint covers the code), but check the validator's output is what you expect, and run `--no-cache` once to be sure.

### Working here

- Work on a branch and open a pull request; do not push to `main`. One pull request is one piece of work, and is called by its number.
- Run `tools/check.sh` before opening one. Then serve its web build and play the affected route on the user's machine. Say in the pull request what was not checked (anything a person has to play).
- Update `docs/design/game-design.md` when behaviour changes, and this file when the layout, a rule above, or a command changes.
- Do not playtest inside a cloud agent environment. A headless or brief launch to confirm it runs is fine.
- Put what nobody has played in `docs/testing-checklist.md`, and take it out once it has been played.
