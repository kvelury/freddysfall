# Freddy's Fall

Godot 4.7 game. What the game is, and the rules it is built to, are in [docs/design/game-design.md](docs/design/game-design.md). This file is the project: how it is laid out, how to run it, and how to check it.

## Requirements

[Godot 4.7](https://godotengine.org/) with the web export templates installed. Python 3 serves the exported page.

`project.godot` asks for feature `4.7` and the GL Compatibility renderer.

## Run

Open the project in the editor and press Play. The main scene is `res://src/world/world.tscn`.

Start in any room instead of the first: `godot --path . -- --room=3`. In a debug build, F4, then a room number and Enter, jumps to that room while playing. On the web build, add `?room=3` to the address. A game started in a chosen room does not read or write the save.

The game saves by itself when a room is entered, when a pickup or token is taken, and when a 3TM finishes, to `user://save.json` (the browser's IndexedDB on the web). To start over, run with `--new-game`, or add `?new-game=1` on the web; the next autosave replaces the old save.

## Web

The Web preset in `export_presets.cfg` turns thread support off, so the page does not need cross-origin isolation headers. A static server is enough.

Room files are plain text. The preset's `include_filter` is `*.txt` so those files are packed into the export. Without that, `res://data/rooms/` is missing from the web build.

```sh
./tools/build_web.sh
./tools/serve.sh
```

`build_web.sh` imports the project, exports a release build to `build/web/index.html`, and injects a listener that keeps Tab from leaving the canvas. `serve.sh` serves that directory at http://localhost:8060. It also tries `open`, which launches the page on macOS. `build/` is gitignored.

## Tests

The tests are `SceneTree` scripts. Each quits with status 0 on success.

```sh
godot --headless --path . --script tests/reach_test.gd
godot --headless --path . --script tests/physics_test.gd
godot --headless --path . --script tests/parity_test.gd
godot --headless --path . --script tests/door_test.gd
godot --headless --path . --script tests/shaft_test.gd
godot --headless --path . --script tests/hazard_test.gd
godot --headless --path . --script tests/entity_test.gd
godot --headless --path . --script tests/save_test.gd
godot --headless --path . --script tests/token_test.gd
godot --headless --path . --script tests/machine_test.gd
godot --headless --path . --script tests/imprint_test.gd
godot --headless --path . --script tests/imprint_play_test.gd
godot --headless --path . --script tests/imprint_solver_test.gd
./tools/validate.sh
./tools/render.sh
./tools/snap.sh 3
```

| Script | What it drives |
| --- | --- |
| `tests/reach_test.gd` | `MovementSim` against the room rectangles, door links, and camera clamp. Prints `RESULT pass`. |
| `tests/physics_test.gd` | The player scene through room 1, jump by jump, and out its door. Prints `PHYSICS pass`. |
| `tests/parity_test.gd` | Replays input plans through the player and through the solver's simulator. They must end within 0.01 px. Prints `PARITY pass`. |
| `tests/door_test.gd` | The player walks through the door from room 2 to room 3 and back. Prints `DOOR pass`. |
| `tests/shaft_test.gd` | The player drops down the hole in room 3 into room 4 and climbs back up, keeping speed through the doors. Prints `SHAFT pass`. |
| `tests/hazard_test.gd` | Spikes and falling out of a room shatter the player and put them back on safe floor. An Imprint over spikes that breaks under the player does not leave a respawn in the air, and a bad respawn spot is stepped back from. Prints `HAZARD pass`. |
| `tests/entity_test.gd` | The room header: the legend and the `exits:` rule, tokens and 3TMs. A valid one loads, and each way of writing one wrong is an error with its line. Prints `ENTITY pass`. |
| `tests/save_test.gd` | `Abilities`, `GameState`, and the save file: round trip, tokens and machines, damaged, newer, older, and missing-room files. Uses its own file. Prints `SAVE pass`. |
| `tests/token_test.gd` | Room 2's doors are blocked until its token is taken, the blocks stop the player and then open, tokens show on the body, a full pocket leaves the next token, and a new game from the save has the token spent. Prints `TOKEN pass`. |
| `tests/machine_test.gd` | The 3TM in room 4: how full it is, tokens flying in one at a time, the third giving Imprint, a spent machine doing nothing, and a save keeping its fill. Prints `MACHINE pass`. |
| `tests/imprint_test.gd` | Where an Imprint platform may go (every refusal), whether the player can land on one, and the blink. Prints `IMPRINT pass`. |
| `tests/imprint_play_test.gd` | Imprint in room 5: locked until found, placed by the action, solid under the player, replaced, broken by time, cleared on leaving a room and on dying. Prints `IMPRINTPLAY pass`. |
| `tests/imprint_solver_test.gd` | The solver with Imprint, on strings: a pit too wide to jump is shut without Imprint and open with it, a platform that breaks too soon is no use, `~` cells forbid it, a room reports the pickup it needs, a room that holds its doors shut waits for its token, and three tokens and a 3TM give Imprint. Prints `IMPRINTSOLVER pass`. |
| `tests/validate.gd` | Loads the whole world, then solves it: every room and door reachable from the start, nowhere to get stuck. Lists every problem and exits 1 if there is one. Run through `tools/validate.sh`. |
| `tests/start_test.gd` | Starting in a chosen room and `warp_to` on the world scene. Prints `START pass`. |
| `tests/render.gd` | Draws each room and the world map as PNGs in `build/renders/`, marking unreachable ledges, traps, sealed doors, blocked doors, and 3TMs. Run through `tools/render.sh`, optionally with room ids: `tools/render.sh 3 4`. |

`reach_test.gd` builds small worlds from strings to check every way a room file can be wrong and that the solver finds a shelf out of reach, a trap, and a door in the sky. It does not instance the world. The other two do, and they set `Player.scripted` so input comes from the test instead of the keyboard.

## Layout

| Path | Role |
| --- | --- |
| `project.godot` | Application `Freddysfall` 0.1.0, autoloads, display, input actions, 60 Hz physics. |
| `data/world.json` | Start room, and each room's id and `grid_pos`. The file is `data/rooms/<id>.txt`. |
| `data/rooms/` | One ASCII file per room. |
| `src/autoload/world_data.gd` | Reads `world.json` and the room files, keeps the rooms and `errors`. |
| `src/world/room_parser.gd` | Pure text-to-`RoomInfo`: checks glyphs and walls, merges `#` into rectangles, pairs and seals doors. |
| `src/world/tiles.gd` | The glyph table. |
| `src/world/reach_graph.gd` | The solver: finds ledges, tries jumps, drops and walks between them with `MovementSim`, and reports what cannot be reached or left. |
| `src/world/room_info.gd`, `door.gd` | A loaded room, and one opening in its wall. |
| `src/autoload/game_state.gd` | Current room, visited set, and session ability values. |
| `src/core/grid.gd` | Cell and screen size, camera clamp. |
| `src/player/` | `MovementConfig` (`movement.tres`), `MovementSim`, and the player scene. The player and the reach solver advance a body with the same `MovementSim.step`. |
| `src/world/` | World scene, room construction, exit halo, and the loader classes above. |
| `src/ui/` | Map overlay and the F3 readout. |
| `AGENTS.md` | How an agent works here, including turning a drawing into a room. `CLAUDE.md` points at it. |
| `docs/design/game-design.md` | Design record. |
| `docs/plans/` | Implementation plans for work that is specified and not built. |

Input action names are `move_left`, `move_right`, `move_down`, `jump`, `map`, and `debug`. What those keys do in the game is in the design doc.
