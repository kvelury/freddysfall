# Freddy's Fall: guide for agents

Godot 4.7, GDScript. A metroidvania whose rooms are ASCII files. What the game is: `docs/design/game-design.md`. The order work is done in: `docs/plans/foundation.md`. How to run and test, how the code fits together, and the rules the code keeps: `README.md`. How each system is built and why it was decided that way: the design doc's "Implementation reference" and "Decision log". Read those before changing code; their rules and guardrails are not suggestions, and a change that makes one untrue updates it in the same pull request.

## Commands

Run from the repo root.

| Command | What it does |
| --- | --- |
| `tools/check.sh` | The complete automated gate before a pull request: imports once, runs all 24 headless tests, validates the world without cache, builds the release web export, and checks its room data and cache-tagged files. CI runs this command too. It leaves `build/web/` ready for `tools/serve.sh` and the user's playthrough. |
| `tools/validate.sh` | Loads every room and solves the world, with Imprint, taking pickups and tokens as it goes. A room is not done until this exits 0. It also prints what each room, ledge and pickup needs, and where the time went. What it works out about each room is kept in `build/solver-cache/`, so a run after editing one room only redoes that room (landing checks are not cached; timings depend on the layout); `--no-cache` ignores it, and deleting `build/` clears it. |
| `tools/pixel_check.sh` | Draws scripted scenarios with a renderer (it uses `xvfb-run` with no display) and checks the world is on whole world pixels and equal to the 320×180 baseline. Run it after any change to how something is drawn; `--baseline` records the baseline on a commit that still draws at 320×180. Not part of `check.sh`. |
| `tools/render.sh [ids]` | PNGs of rooms and the world map in `build/renders/`. Read them to see what you built. |
| `tools/snap.sh <id>` | A real in-game frame of a room in `build/snaps/`. Opens a window for a second, so run it on the user's machine. |
| `godot --headless --path . --script tests/<name>.gd` | Run one test; each file in `tests/` is one (`tools/check.sh` lists the 24 it runs). Prints a pass line and exits 0. |
| `godot --path . -- --room=<id>` | Play starting in a room. In the browser, `?room=<id>`. Use `--dev --room=<id>` or `?dev=1&room=<id>` for tools; F2 opens the panel, F4 the protected room picker. |
| `tools/build_web.sh` then `tools/serve.sh` | The browser build at http://localhost:8060. |

After adding a script with a `class_name`, run `godot --headless --path . --import` once. A headless script cannot see the new class until then. `validate.sh` and `render.sh` do this for you.

## Playtesting

Do not playtest Freddy's Fall inside the Cloud Agent environment, and do not record a playtest video, unless the user explicitly asks. A headless or brief launch to confirm the game runs is fine. Manual playtesting should be started on the user's computer, using a local agent when needed, so the user can play it themselves.

## Room files and the movement envelope

The room file format (glyphs, doors, the legend) and the movement envelope are in `data/rooms/AGENTS.md`, which loads when you work on room files. Read it before adding or editing a room, or translating a drawing.

## Adding a room from a drawing

The user draws rooms on graph paper, numbers each one, and shares a photo. The squares are not 10 px cells and the drawing is not a fixed size, so translation is a judgement. The rule is that **every judgement is reported**.

1. **Read the room number** from the photo, and where the room sits relative to rooms that exist: the user's note ("right of 4, bottom screen"), or an overview sheet. That sets `grid_pos`. If you cannot tell, ask.
2. **Pick the size.** Count the drawn room's squares across and down. Choose the whole-screen size W x H whose 32W : 18H shape best matches the drawing. Scale is cells per square. Round each feature to the nearest cell.
3. **Line up the doors.** Put a door on the wall that faces each neighbor, matching the neighbor's existing door in position and thickness. Do not move or edit an existing room unless the user says to.
4. **Run `tools/validate.sh`.** Fix an unreachable jump by nudging a platform at most 2 cells. Anything bigger is a question for the user, not a redesign.
5. **Render the room** with `tools/render.sh <id>`, read the PNG, and reply with it and a **translation report**:
   - the size you chose (for example "2 x 1 screens, 64 x 18 cells") and the scale ("1 drawn square = 2 cells")
   - every rounding and every nudge, as a list ("lower platform moved 1 cell left so the jump from the floor works")
   - anything you could not read in the drawing and what you assumed
   - validator result and any warnings
6. **Commit only after the user approves.** One room per commit, on a branch.

## What to draw (for the user)

- Graph paper. Draw each screen of a room as a box. One box is 32 squares wide and 18 tall if you want it exact, but any size works.
- Write the room's number in a corner.
- Mark every door on the wall where it is, and draw it as a gap in the wall.
- If a room is more than one screen, say so ("2 x 1").
- Mark where the player starts in the first room.
- Say where the room sits next to the others, or draw an overview sheet with the room numbers.
- Use a key for anything that is not a wall, a platform or a door (pickups, hazards, no-imprint areas) and keep it the same from drawing to drawing.

## Working on the repo

- Work on a branch and open a pull request. Do not push to `main`.
- Run `tools/validate.sh` and the tests before opening one.
- When behavior changes, update `docs/design/game-design.md` in the same pull request, so it stays true.
- **Imprint is never replaced or refreshed by another click.** While one stands, no other goes down until it has broken (plus `imprint_cooldown`). Any feature touching Imprint, footing, timers or waiting must keep this rule, in the runtime and the solver. See "The Imprint rule" under Guardrails in the design doc. Loosening it is the user's decision. A platform shrinks toward where the player stood when they placed it (the block nearest them lasts, ties go to the block they face), and the solver counts only that last block as footing.


## Dev tools are part of every gameplay feature

This requirement always applies to work on abilities, upgrades, effects, resources
and progression restrictions. A feature is not complete until it can be set up
immediately in isolated playtesting, removed/reset, retried, and round-tripped in a
named loadout where applicable. Include this support, tests and documentation in
the same PR. An intentionally unsupported feature needs an explicit reason.

- Add `dev` control metadata to every upgrade in `data/upgrades.json`. Supported
  types are `bool`, `int`, `float`, `effects`, and `unsupported` (requires `reason`).
  Numeric controls declare bounds, step and units; effects distinguish implemented
  names from planned names. Do not expose a planned name as a functioning power.
- Register ability fields in `Abilities.STATS`, `to_dict`, `from_dict`, and the dev
  catalog. `dev_catalog_test` checks registry coverage, serialization, and actual
  ability properties; do not remove these checks to get a new feature through.
- Add custom resources/commands through the shared dev catalog/session boundary.
  Respect gameplay caps. Test increases, decreases/removal, invalid edits,
  notifications, retry state, loadout compatibility and normal-save isolation.
- Do not set test abilities by editing room files or the normal save. Use F2,
  `?dev=1&room=<id>` or `--dev --room=<id>`. All test sessions block save reads,
  writes and erasure at the save boundary. `new-game` must not override isolation.
- Retries restore the original test room and captured progression, overlaid with
  the latest explicitly applied loadout. New progression fields must join the
  snapshot; consumed live resources must not silently overwrite selected values.
- Door bypass is runtime-only. Keep `ExitRules` and the progression solver pure;
  a bypass must not fabricate flags or make normal validation easier.
- Keep `README.md`, the game design's Dev playtesting/implementation/decision
  sections, and `docs/testing-checklist.md` current. Historical plans are not the
  authority. `CLAUDE.md` imports these instructions.
