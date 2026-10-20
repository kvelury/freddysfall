# Freddy's Fall — foundation plan before building out the metroidvania

## Context

You want to grow Freddy's Fall into an exploration metroidvania. Rooms will come from photos of notebook drawings (graph paper, any scale, each room numbered) and upgrades like Imprint will gate the paths. The first design review was written against a stale checkout. This plan is re-based on `origin/main` @ `029ab4f`, plus the two unmerged Cursor branches. It orders every fix so that each chunk makes the next one cheaper, and so that adding rooms from drawings is reliable before you start drawing seriously.

### What changed since the first review (origin/main vs. what I reviewed)

| Review item | Status on origin/main |
|---|---|
| Room C (now room 3) softlock | **Fixed.** Rooms 2↔3 now connect by a floor-level side door. `route_test.gd` walks 1→2→3→2→1. |
| Numbered room ids | **Done.** `data/rooms/1.txt`… `world.json` still carries a redundant `file` field. |
| Design doc committed, README stale | **Done.** `docs/design/game-design.md` plus a rewritten README. The local untracked `docs/design/technical-design.md` is an older draft of the same doc. |
| Vertical doors teleport to spawn and zero velocity | **Latent.** main has no vertical doors right now, but the bug is still in `stand_cell_for_rect` / `player.gd:42`. Branches `cursor/vertical-door-landing-9eb7` and `cursor/room-4-return-door-9eb7` build a suck-and-land alternative on the old a/b/c rooms. They conflict with main and are superseded by decision D1. |
| Web build serves a stale pack after rebuild | **Fixed on a branch only.** Commit `c73714d` on `room-4-return-door` (only touches `tools/build_web.sh`). |
| Agent guide | **On a branch only.** `cursor/playtest-preference-2a64` adds `AGENTS.md` with a playtest preference. |
| Silent load failures, unknown glyphs become air, walk out of the world, two collision systems, hand-coded coordinate tests, untyped dicts, no entities/save/respawn | **Unchanged.** Hand-coded tests are now worse: `route_test.gd` is 214 lines of pixel waypoints for 3 rooms. |

### Decisions (✅ = you chose; ◻ = my default, approve or change)

- ✅ **D1 Vertical doors keep momentum.** The player keeps their world position and velocity across any door, nudged inward. Going up gets a minimum upward speed. Close both vertical-door branches without merging.
- ✅ **D2 One collision resolver.** The player moves via `MovementSim`, so the game and the validator/Imprint check are identical by construction.
- ✅ **D3 Legend header in the room `.txt`** for entities that need settings.
- ✅ **D4 Graph paper, any scale.** The agent picks the scale and the whole-screen size, and reports every rounding.
- ◻ **D5 Keep `world.json` + `grid_pos`** (drop `file`, implied as `data/rooms/<id>.txt`). No ASCII world map; the renderer draws the world PNG for checking instead.
- ◻ **D6 Agent guide = `AGENTS.md`** (Cursor reads it), with a one-line `CLAUDE.md` that imports it (`@AGENTS.md`). Fold in the playtest preference from the branch.
- ◻ **D7 Save = autosave on every room entry** to `user://save.json` (works on web via IndexedDB). A save-point glyph can come later if you want it.
- ◻ **D8 Respawn = last safe ground.** Hazards, pits and leaving room bounds send you to the last floor you stood on, Hollow Knight style.
- ◻ **D9 Imprint input decisions** (mouse button, gamepad cursor, illegal-cell look) wait until the Imprint chunk. They are already on the design doc's "Not decided" list.
- ◻ **D10 Deferred:** L-shaped rooms, map scrolling/icons, lazy solid merging, palettes. Revisit once there are ~20 rooms.

---

## Chunks (one PR each, in order)

### Chunk 0: Sync and salvage (small)
- `git pull` main. Delete the untracked `docs/design/technical-design.md` (superseded by `game-design.md`; diff confirmed it is only an older draft).
- Cherry-pick `c73714d` (web cache-busting in `tools/build_web.sh`).
- Run all three tests on main for a baseline.
- After you confirm, delete the remote branches `vertical-door-landing`, `room-4-return-door`, `floor-level-room-link` and `game-design-doc` (the last two are already merged). Fold `AGENTS.md` into Chunk 3.
- Save this plan as `docs/plans/foundation.md` so Cursor agents see it too.

### Chunk 1: Loader you can trust
Goal: bad room data can never load quietly.
- Split `src/autoload/world_data.gd` (365 lines) into:
  - `src/world/room_info.gd`: `class_name RoomInfo`, typed fields
  - `src/world/door.gd`: `class_name Door`, replacing the exit dictionaries (`edge`, `rect`, `screen`, `dest_id`, `dest_rect`)
  - `src/world/room_parser.gd`: pure static functions that take text and return `RoomInfo` plus errors. Reuse `_merge_solids`, `_parse_exits`, `_screen_cell` and `_link_exits` logic as-is.
  - `WorldData`: a thin registry.
- **Tile registry** `src/world/tiles.gd`: one table, glyph → `{solid, hazard, no_imprint, door, spawn}`. It replaces the scattered `"#"`, `"X"`, `"P"` and `"~"` literals in `world_data.gd`, `room.gd` and the `is_solid` check.
- **Errors are collected**, not `push_error`-and-continue: `WorldData.errors: Array[String]`. In debug builds, a non-empty list shows on screen.
- New load rules:
  - an unknown glyph is an error
  - every edge cell must be `#` or `X`
  - `X` with no neighbour is built as solid (no halo, no hole)
  - the start room must contain `P`
  - room sizes and overlaps stay as they are today
- Type `Room.info` (`room.gd:6`) and the map's `info` parameters.
- **`tools/validate.sh`** → `tests/validate.gd`. Loads the world and exits non-zero on any error.
- Tests: add parser unit cases to `reach_test.gd` (bad glyph, open edge, dead-end door, overlap) using in-memory text.

### Chunk 2: Automatic reachability and room renders
Goal: replace hand-placed coordinates with a solver that proves every room works. Also give agents and you a picture to check.
- **`src/world/reach_graph.gd`**:
  - Nodes = *ledges* (maximal horizontal runs of standable cells: empty, with solid below and room for the body) and doors.
  - Edges come from `MovementSim.simulate_jump`, sampled over:
    - start x on a ledge (ends, plus every 2 cells)
    - input −1/0/+1
    - hold frames {3, 8, 90}
    - standing and running start
    - walk-off drops with no jump
  - Extend `simulate_jump` to record when the path touches a door's trigger rect.
  - The ability set is a parameter (empty for now), ready for Imprint later.
- Validator checks across the whole world, from the start `P`:
  - every room and every door can be reached
  - **no softlocks**: from every reachable ledge, the player can still get back to a door they arrived by, so the old room-C softlock would have failed here
  - ledges no jump can reach show up as warnings
- **`tools/render.sh`** → `tests/render.gd`, headless `Image.save_png` to `build/renders/`:
  - one PNG per room at 4 px/cell, with grid lines every 5 cells, the room number in a 3×5 pixel font, doors, `P`, and unreachable ledges highlighted
  - `world.png` laid out by `grid_pos`
- Remove the hand-coded jump assertions from `reach_test.gd` and delete `route_test.gd`. Both become "solver says room N is fully reachable". Keep `physics_test.gd` as the single real-scene smoke test.
- Risk: solver speed in GDScript. Budget under 5 s for the whole world. Tune sampling, and cache per room by file hash if needed.

### Chunk 3: The drawing-to-room workflow
Goal: you can start handing over notebook photos after this chunk.
- **`AGENTS.md`** (plus `CLAUDE.md` → `@AGENTS.md`):
  - glyph legend, screen 32×18
  - movement envelope: a full jump rises ~5 cells, a running jump crosses ~7, a tap is ~1.5
  - door pairing rules
  - commands: validate, render, test, snap
  - the playtest preference from the branch
  - the translation protocol below
- **Translation protocol (graph paper, any scale)**:
  1. Read the room number from the photo, and where it sits (your note, e.g. "right of 4, bottom screen", or an overview sheet). Set `grid_pos`.
  2. Count the drawn room's squares. Pick the whole-screen size W×H whose 32W:18H ratio best matches. Scale = cells per square. Round features to the nearest cell.
  3. Snap doors to line up with the neighbour's existing door. Never move an existing room unless you say so.
  4. Run the validator. Fix unreachable jumps with nudges of at most 2 cells. Anything bigger is a question to you, not a silent redesign.
  5. Render the room. Reply with the PNG and a **translation report**: size chosen, scale, and every rounding or nudge, as a list.
  6. Commit only after you approve.
- Add a drawing cheat-sheet section to `AGENTS.md` for your side: mark doors clearly, write the room number, optionally write the size in screens ("2×1") to remove guesswork, and use a key for pickups/hazards.
- **Start anywhere**:
  - `godot --path . -- --room=12` starts in room 12, at `P` or else beside its first door
  - in debug builds, F4 + digits + Enter warps to a room
  - `world.gd` parses `OS.get_cmdline_user_args()`
- **`tools/snap.sh <room>`**: `godot --path . --write-movie build/snaps/<room>.png --fixed-fps 60 --quit-after 30 -- --room=<room>`, for a real in-game frame (runs locally, not in the cloud).
- Update the README test table and the design doc's Rooms section.

### Chunk 4: One collision resolver (D2)
- The player stops calling `move_and_slide`. `player.gd` gets the room's pixel rects from the current `Room` (and later the active imprints), then calls `MovementSim.resolve`.
- Move corner correction (`player.gd:94-120`) into `MovementSim` as a pure function over rects, so `simulate_jump` gets it too.
- Ground check = probe 1 px down in the resolver, replacing `_on_ground`'s `test_move` and `floor_snap_length`.
- Keep `CharacterBody2D` only if something still needs it. Otherwise the player becomes a `Node2D` with an AABB. Exit `Area2D`s switch to rect checks in `Room`, which removes the deferred physics-flush workaround in `world.gd:54-56`.
- Physics interpolation is kept: the player still moves in `_physics_process`.
- Verify: `physics_test.gd` and the solver agree. Add a test that replays one recorded input sequence through both the player and `simulate_jump` and checks they match to 0.01 px.

### Chunk 5: Doors with momentum, hazards, respawn (D1, D8)
- Transition (`world.gd:_begin_transition`):
  - keep `player.global_position` (already in world coordinates) and push it ≥ half a cell past the door plane into the new room
  - keep velocity
  - for an `up` exit, `velocity.y = min(velocity.y, -UP_BOOST)`
  - the camera slides as today; input is restored with velocity intact
- Delete `stand_cell_for_entry`, `stand_cell_for_rect`, `_stand_on` and the spawn fallback.
- Validator rule: an `up` door must lead to a ledge the boosted entry can reach. A `down` door must not drop into a hazard or a void.
- Tiles: add `^` hazard. Track the last safe floor (the last grounded ledge that is not a hazard and not right beside a door). On a hazard, or leaving room bounds, play a short shatter or flash and move the player to the last safe floor.
- Add a vertical shaft pair (e.g. rooms 4 and 5 under room 3) as content that exercises up and down doors. The solver proves it.

### Chunk 6: Entities, upgrades and save (D3, D7)
- Room file format:
  ```
  legend:
    U = pickup id=r12_width upgrade=imprint_width value=3
  ---
  ################################
  ```
  The `legend:` block is optional. Its glyphs extend the tile registry for that room only. `id` is required and stable, never derived from x,y.
- `src/world/entities/`: `Pickup` first. `Room.build` spawns entities from the legend through a type → script registry, and skips any that `GameState` says are already collected.
- `data/upgrades.json`: upgrade id → stat and value. `GameState.abilities` becomes a typed `Abilities` resource with an `abilities_changed` signal, plus `flags: Dictionary` for collected and opened things.
- `src/autoload/save.gd`: serializes visited rooms, abilities, flags and the current room + entry. Autosaves on room entry and loads on boot. The save is versioned so the format can change later.
- The reach solver takes `Abilities`. The validator reports per room: "needs: imprint_width≥3".

### Chunk 7: Imprint (its own plan doc)
Split in two. **7a, the playable Imprint, is built**: the D9 questions are settled in `game-design.md` (left click, mouse only, solid, refuses spikes and doors, found as a pickup). **7b, the solver and validator using Imprint and the "needs" report, is built** (room 6 is the first room that Imprint opens).
- Settle the D9 questions first, then build to the existing spec in `game-design.md`.
- The reachable/unreachable cursor uses `reach_graph`/`simulate_jump` from the player's live state, against room rects plus the imprint. Thanks to Chunk 4 it is exact.

### Chunk 8: exit rules, tokens and the 3TM (built)
Added after the first seven. A room can hold its doors shut until a rule is met (`exits: pickups`), tokens are carried up to three and shown on the player's body, and a 3TM takes three tokens and gives an upgrade. Imprint is now earned that way, and the world was reshuffled to match: old room 5 is gone, old room 6 is room 5, and a new empty room 6 sits behind it.

### PR #17: the new world map
The world was redrawn. Rooms 5 and 6 come from the user's drawings, room 4 moved left to meet room 5, room 2 got a floor door down to room 5, and room 7 is a long empty fall marked `trap: allowed`. Work is called by PR number from here on, not by chunk.

### Later (D10)
Unused screens for L-shaped rooms, map panning and icons, lazy `_merge_solids` (it's O(n²)), the duotone palettes (the plan already exists).

---

## Critical files
- `src/autoload/world_data.gd` → split (Chunk 1)
- `src/world/room.gd`, `src/world/world.gd`: tiles, entities, transitions (Chunks 1, 4, 5, 6)
- `src/player/player.gd`, `src/player/movement_sim.gd`: resolver and corner correction (Chunk 4); door-touch tracking in `simulate_jump` (Chunk 2)
- `src/autoload/game_state.gd`: abilities, flags, save (Chunk 6)
- `tests/`: new `validate.gd` and `render.gd`; `reach_test.gd` slimmed down; `route_test.gd` removed; `physics_test.gd` kept
- `tools/`: new `validate.sh`, `render.sh`, `snap.sh`
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/design/game-design.md`, `docs/plans/foundation.md`

## Verification (every chunk)
- `godot --headless --path . --script tests/reach_test.gd`, `tests/physics_test.gd` and `tests/validate.gd` all exit 0 (plus `route_test.gd` until Chunk 2 removes it).
- `tools/render.sh` and a look at the PNGs once Chunk 2 lands.
- `./tools/build_web.sh && ./tools/serve.sh`, then a short local play of the rooms the chunk touched. You play it yourself, per the playtest preference.
- Each chunk updates `game-design.md` wherever it changes behaviour (doors, collision, glyphs), so the design record stays true.

**PR #18** changed how Imprint looks and nothing else: the cursor is always a dotted outline (the filled look and the sparkle are gone for now), placed platforms draw over the cursor, and the dashes on a platform count down its life.
