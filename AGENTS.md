# Freddy's Fall: guide for agents

Godot 4.7, GDScript. A metroidvania whose rooms are ASCII files. What the game is: `docs/design/game-design.md`. The order work is done in: `docs/plans/foundation.md`. How to run and test, how the code fits together, and the rules the code keeps: `README.md`. How each system is built and why it was decided that way: the design doc's "Implementation reference" and "Decision log". Read those before changing code; their rules and guardrails are not suggestions, and a change that makes one untrue updates it in the same pull request.

## Commands

Run from the repo root.

| Command | What it does |
| --- | --- |
| `tools/check.sh` | The complete automated gate before a pull request: imports once, runs every `tests/*_test.gd` in parallel (one Godot process each, `JOBS` at a time, logs in `build/test-logs/`), validates the world with every ledge reachable (a fresh solver cache, warmed by one process per core), builds the release web export, and checks its room data and cache-tagged files. CI runs this command too. It leaves `build/web/` ready for `tools/serve.sh` and the user's playthrough. |
| `tools/validate.sh` | Loads every room and solves the world, taking pickups and tokens as it goes. A room is not done until this exits 0. It also prints what each room, ledge and pickup needs, and where the time went. What it works out about each room is kept in `build/solver-cache/`, so a run after editing one room only redoes that room (landing checks are not cached; timings depend on the layout); `--no-cache` ignores it, and deleting `build/` clears it. |
| `tools/solver_diff.sh <ref>` | Solves the world at `<ref>` and in the working tree without the cache, and diffs everything the solver worked out. Empty output means the two agree. A solver change meant to be exact (a speed-up, a refactor) must leave it empty; paste `validate.sh`'s slowest-rooms table from before and after into the pull request. |
| `tools/pixel_check.sh` | Draws scripted scenarios with a renderer (it uses `xvfb-run` with no display) and checks the world is on whole world pixels and equal to the baseline (kept as 320×180 world pixels). Run it after any change to how something is drawn. When the look is meant to change, record a new baseline with `--baseline` on the commit that changes it and say so in the pull request. Not part of `check.sh`. |
| `tools/render.sh [ids]` | PNGs of rooms and the world map in `build/renders/`. Read them to see what you built. |
| `tools/snap.sh <id>` | A real in-game frame of a room in `build/snaps/`. Opens a window for a second, so run it on the user's machine. |
| `godot --headless --path . --script tests/<name>.gd` | Run one test; each file in `tests/` is one (`tools/check.sh` runs every `tests/*_test.gd`; `tools/check.sh --tests-only` runs just them). Prints a pass line and exits 0. |
| `godot --path . -- --room=<id>` | Play starting in a room. In the browser, `?room=<id>`. A `--room` or `--dev` launch skips the main menu and boots straight into the world, as does `?dev=1`. Use `--dev --room=<id>` or `?dev=1&room=<id>` for tools; F2 opens the panel, F4 the protected room picker and F7 slows the game (dev tests only). |
| `tools/build_web.sh` then `tools/serve.sh` | The browser build at http://localhost:8060. |
| `tools/stage_site.sh` | Turns `build/web` into `build/site`, the folder published to GitHub Pages (real files instead of symlinks, no unused untagged copies). `deploy.yml` runs it after `tools/check.sh` on every merge to `main`. `tools/serve.sh site` serves it. |

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
- Use a key for anything that is not a wall, a platform or a door (pickups, hazards) and keep it the same from drawing to drawing.

## Working on the repo

- Work on a branch and open a pull request. Do not push to `main`.
- Run `tools/validate.sh` and the tests before opening one.
- When behavior changes, update `docs/design/game-design.md` in the same pull request, so it stays true.
- **Imprint is a legacy dev-tools feature, not a core mechanic.** The core mechanics are movement and attack (jumps, Tongue Lash, Tongue Climb). Do not build rooms, puzzles or power-ups on Imprint, and a new feature need not model it: the solver does not, and the room parser refuses a pickup or 3TM that gives it. Where the dev-tools Imprint is touched, it keeps its rule (never replaced or refreshed by another click; see "The Imprint rule" under Guardrails in the design doc).
- **The mouse is only for menus.** Gameplay uses the keyboard or a controller; the cursor is never hidden (a vanishing pointer in a browser tab is confusing) but does nothing in play. Any key or button (not the mouse, not a function key, not a stick) closes a popup such as Game Over or a new power, and its text says "Press any key to continue" ("button" when a controller was used last). New input goes through an InputMap action and `InputBindings`, so it is rebindable in Settings; a stick is digital.


## Code review guidance

Apply this guidance to every Freddy's Fall code review, including PR comments.
It also governs fixes made when addressing review comments.

- Give each actionable finding a severity, exact file and line, concrete trigger,
  observed failure and intended behavior. Verify the relevant callers and state
  transitions; distinguish reproduced failures from risks inferred from code.
- Include exact fix details: name the functions and shared boundaries to change,
  describe the state/collision/data changes and their ordering, and specify the
  regression cases and expected results. Use a small suggested patch when it is
  unambiguous. "Handle collisions" or "reset state" alone is not sufficient.
- Ground fixes in the current README, design implementation reference and decision
  log, and cite the existing implementation that establishes the pattern. Prefer
  the shared movement, collision, ability registry, dev-session and save boundaries
  over duplicated formulas, room-specific exceptions or a second source of truth.
  Explain when an established pattern itself needs to change.
- Design fixes to work as powers combine and rooms grow: use data-driven upgrades
  and room definitions, stable entity IDs and explicit ability/session state.
  Check unlock/removal, bounds, old saves/loadouts, retry, death, warp and room
  transitions where affected. Exercise relevant combinations of movement, attack,
  solids, movers and hazards, including supported maximum speeds and values.
  Keep runtime and solver behavior consistent for modeled mechanics; honor
  explicitly agreed solver limitations and require support before content depends
  on an unmodeled power. Keep pure simulation independent of scene/autoload state.
- Prefer the smallest robust fix that leaves clear extension points for later
  power-ups and levels. Explain material tradeoffs; do not propose speculative
  frameworks or redesign agreed gameplay. Include required dev controls, reset,
  loadout support and documentation in the proposed fix's scope.
- **Browser-window playability is a requirement for every proposed fix.** Preserve
  the release web export and static hosting assumptions, keyboard gameplay,
  focus/input handling, pause/overlays, save isolation and whole-pixel presentation.
  Check window resizing/scaling and practical web performance when affected. Do
  not require fullscreen, native-only APIs, threads or server features to play.
- Name the checks that prove the fix: a focused regression that fails beforehand,
  relevant combination/boundary tests, and the repository gates appropriate to
  the change (`tools/check.sh`, solver diff for exact solver changes, pixel checks
  for drawing changes). For browser/input/export changes, include a served release
  web-build check in an ordinary browser window. Report what actually ran and any
  incomplete checks; a headless pass alone does not establish browser playability.

### Addressing review comments

When the user asks to address code review comments, carry the work through to
the existing PR: implement, verify, commit and push to its head branch, then
resolve each fully addressed review thread. That request authorizes pushing the
fixes and resolving the addressed threads; do not stop at local edits.

- Read each full thread and inspect the current PR head before editing. Follow
  the comment's proposed fix and validation guidance as closely as possible,
  applying the codebase, extensibility and browser-playability rules above.
- If the suggested approach conflicts with current code, established invariants
  or another requested fix, implement the closest correct solution and explain
  the specific deviation in the thread. Do not blindly apply a stale suggestion.
- Run the relevant regression checks and required repository gates. Push the
  verified fix to the PR's head branch, preserving unrelated work; never force
  push or merge merely to address comments.
- After confirming the pushed commit contains the fix, reply in the thread with
  the commit, what changed and validation results, then resolve it. These replies
  are part of the authorized review-comment workflow. Leave partially addressed,
  disputed or blocked threads open and report what remains; do not resolve a
  comment merely because a local edit was made.

## Dev tools are part of every gameplay feature

This requirement always applies to work on abilities, upgrades, effects, resources
and progression restrictions. A feature is not complete until it can be set up
immediately in isolated playtesting, removed/reset, retried, and round-tripped in a
named loadout where applicable. Include this support, tests and documentation in
the same PR. An intentionally unsupported feature needs an explicit reason.

- Every control belongs to a collapsible section of the panel's Player tab. An upgrade's
  `dev` block names one in `section`; `DevCatalog.SECTIONS` lists them (Tokens & hearts,
  Movement, Tongue Lash, Imprint (legacy), Debug view). Add a section there when none fits; a missing
  or unknown one fails `DevCatalog.problems()`. A session switch with no registry entry
  (Classic Imprint, token marks, slow motion, wall strength) is placed in `_build_player`
  under the section it belongs to.
- Add `dev` control metadata to every upgrade in `data/upgrades.json`. Supported
  types are `bool`, `int`, `float`, `effects`, and `unsupported` (requires `reason`).
  Numeric controls declare bounds, step and units; effects distinguish implemented
  names from planned names. Do not expose a planned name as a functioning power.
- Register ability fields as a `var` on `Abilities` (`stats()`, `to_dict` and
  `from_dict` follow from those lines; a floor goes in `CLAMPS`) and in the dev
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
