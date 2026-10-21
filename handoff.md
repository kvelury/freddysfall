# Handoff: scalable local checks and progression solver

## Purpose

This is the implementation plan for the next agent. It covers the three items
agreed after the scalability audit:

1. Keep the existing browser build and human playthrough as the end-to-end
   check.
2. Add one local command that runs every automated check and leaves a fresh web
   build ready to play.
3. Remove the progression solver's silent eight-round ceiling.

Do not turn this into a general architecture rewrite. The current room format,
runtime room lifecycle, movement simulator, save format, solver cache, and
manual browser workflow are working and should remain.

## Starting point

- Base this work on `main` at or after `06b618e` (PR #22).
- Read, in order:
  1. `README.md`
  2. `docs/design/game-design.md`, especially **Checking rooms**,
     **Implementation reference**, and **Decision log**
  3. `AGENTS.md`
  4. `src/world/reach_graph.gd`
  5. `tests/imprint_solver_test.gd`
  6. `tests/validate.gd`
  7. `src/world/solver_cache.gd`
- Work on a branch. Do not push to `main`.
- Keep the work in one pull request, but use separate commits for the local
  check command and the solver change.

The current browser build is known to work and is regularly played by the
owner. PR #22 changed validator caching and documentation, not browser
gameplay. The work below should protect that workflow, not replace it.

## Existing architecture to preserve

- Rooms remain ASCII files under `data/rooms/`, placed by `data/world.json`.
- `MovementSim` remains the one movement implementation shared by the player,
  reach solver, and Imprint checks.
- The running game keeps only the current room, plus the destination room
  during a transition.
- Stable legend IDs remain the save identity of pickups, tokens, and 3TMs.
- `Save.VERSION` changes only when the save shape changes. This work does not
  change the save.
- Tests continue to run without the persistent solver cache.
- `tools/validate.sh` continues to support both cached validation and
  `--no-cache`.
- `SolverCache.SOLVER_FILES` already includes
  `src/world/reach_graph.gd`. Changing the solve loop must therefore
  invalidate old cache files automatically. Do not add a second cache version
  or manual invalidation rule for this work.

## 1. Preserve the browser build and playthrough workflow

### Goal

The owner should still finish each change by playing the real release build in
a browser. Automated checks run before that playthrough and catch mechanical
failures; they do not claim that the game feels or looks right.

The intended workflow after this work is:

```sh
./tools/check.sh
./tools/serve.sh
```

Then open <http://localhost:8060> and play the affected path. `check.sh` should
leave the release export in `build/web/`, so it must not delete or replace the
web build after checking it.

### What the human playthrough remains responsible for

- Movement feel, including short and full jumps.
- Door placement, momentum, and camera transitions.
- Whether a room communicates its intended route.
- Pickup, token, 3TM, and Imprint feedback.
- Map readability and zoom.
- Visual effects and timing.
- Browser save and reload through IndexedDB.
- Browser input and focus behavior.
- Any item still open in `docs/testing-checklist.md`.

Do not add Playwright, Selenium, browser-driving code, or a GitHub Actions
workflow in this work. The owner already performs the browser playthrough.
Those systems would add maintenance without replacing the judgment the
playthrough provides.

### Documentation changes for this workflow

Update:

- `README.md`
  - Put `tools/check.sh` first in **Checking your work**.
  - Explain that it runs the full headless suite, an uncached world
    validation, and a release web build/integrity check.
  - State that `tools/serve.sh` and a human playthrough follow it.
- `AGENTS.md`
  - Add `tools/check.sh` to the command table.
  - Preserve the rule that cloud agents do not playtest unless explicitly
    asked. A cloud agent may run headless checks and build the release export;
    the user or a local agent performs the playthrough.

Do not rewrite `docs/testing-checklist.md` merely because the command exists.
Only mark an item as tried after a person actually tries it.

## 2. Add one local automated check command

### Goal

Add `tools/check.sh` as the single command an agent runs before handing a build
to the owner. It must fail immediately when any test, world validation, export,
or export-integrity check fails.

Use POSIX shell, matching the existing tools:

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
```

Make the file executable.

### Exact automated checks

`tools/check.sh` should perform these steps in this order.

#### A. Import once before direct test scripts

```sh
godot --headless --path . --import
```

This makes newly added `class_name` scripts visible to the headless test
scripts. Do not hide a failed import. Normal import output may remain visible
unless it is excessively noisy.

#### B. Run all 16 `*_test.gd` scripts

Keep an explicit, deterministic list. Do not depend on shell glob order, and
do not accidentally include `tests/validate.gd` or `tests/render.gd`.

The current complete list is:

```text
reach_test.gd
physics_test.gd
parity_test.gd
door_test.gd
shaft_test.gd
hazard_test.gd
start_test.gd
entity_test.gd
save_test.gd
map_test.gd
cache_test.gd
token_test.gd
machine_test.gd
imprint_test.gd
imprint_play_test.gd
imprint_solver_test.gd
```

For each:

```sh
godot --headless --path . --script "tests/$test"
```

Because the script uses `set -e`, the first non-zero result stops the command.
Print a short line before each script so a failure is easy to locate.

Do not run these tests against `build/solver-cache/`. Their current design
leaves `ReachGraph.cache` unset, and `cache_test.gd` uses its own temporary
cache path.

#### C. Validate the whole world without cache

Run:

```sh
./tools/validate.sh --no-cache
```

The uncached path is intentional. It proves the result does not depend on
stale local files and does not write the cache. Keep ordinary
`tools/validate.sh` available for the fast room-authoring loop.

Do not make `check.sh` run cached validation as a second correctness check.
`tests/cache_test.gd` already proves cached and uncached reports agree, and a
second whole-world solve would add time without new coverage.

#### D. Build the release web export

Run:

```sh
./tools/build_web.sh
```

Use the existing build script rather than duplicating its import, export,
Tab-key patch, or cache-tag logic.

#### E. Check the generated export

After the build, check at least all of the following:

- `build/web/index.html` exists and is non-empty.
- `build/web/index.js` exists and is non-empty.
- `build/web/index.pck` exists and is non-empty.
- `build/web/index.wasm` exists and is non-empty.
- `index.html` contains the injected Tab listener
  (`e.key==='Tab'`).
- `index.html` contains an `index.js?v=<digest>` URL, where `<digest>` is
  exactly 12 lowercase hexadecimal digits.
- Read the `"executable":"<tag>"` value from `index.html`, where `<tag>` is
  `g<digest>`. Assert that this digest is the same one used by the JavaScript
  URL.
- The following files for that exact tag exist, are non-empty, and resolve if
  they are symlinks:
  - `<tag>.pck`
  - `<tag>.wasm`
  - `<tag>.audio.worklet.js`
  - `<tag>.audio.position.worklet.js`
- The tagged PCK and original `index.pck` have the same size.
- The tagged WASM and original `index.wasm` have the same size.
- `export_presets.cfg` still contains `include_filter="*.txt"`, because the
  browser build otherwise omits `data/rooms/*.txt`.

It is acceptable to use a small Python heredoc inside `tools/check.sh`, as
`tools/build_web.sh` already requires Python and uses that pattern. Raise a
plain assertion/error naming the missing or inconsistent artifact.

Prefer checking the output over changing `tools/build_web.sh`. In particular,
do not replace its cache-tag symlinks in this work unless the check exposes a
real failure.

If Godot can reliably launch the exported PCK headlessly on the development
platform, add this as a final smoke check:

```sh
godot --headless --main-pack build/web/index.pck --quit-after 2
```

Prototype that command before committing it. Keep it only if:

- it actually loads the exported project rather than the source checkout;
- missing room files cause a non-zero result or a detectable load error; and
- it exits consistently in local and cloud environments.

If those conditions are not true, omit the PCK launch and document that room
loading is covered by the source tests plus `include_filter` check and by the
human browser playthrough. Do not add a fragile check just to claim deeper
coverage.

### Output

The command should finish with one unmistakable line, for example:

```text
CHECK pass: 16 tests, uncached world validation, and web export
```

Do not parse individual tests' pass text. Their process exit codes are the
contract.

### Tests for `tools/check.sh`

Run the command once from a clean state and once with an existing
`build/web/`. Both runs must pass.

Mutation-check the script before restoring it:

1. Temporarily change one test name to a missing file; `check.sh` must fail.
2. Temporarily change the expected Tab-listener text; the export check must
   fail.
3. Temporarily point one tagged artifact check at a missing file; it must fail.
4. Restore every mutation and run the complete command again.

Do not commit mutation changes or generated `build/` files.

## 3. Remove the solver's eight-round ceiling

### The current problem

`ReachGraph.solve()` currently contains:

```gdscript
const MAX_ROUNDS := 8

for round in MAX_ROUNDS:
    # analyze with the things taken so far
    # collect newly reachable things
```

A round means:

1. Apply the upgrades from every reachable thing collected in earlier rounds.
2. Analyze the world with those abilities.
3. Record newly reachable pickups, tokens, and 3TMs.
4. Repeat if those things changed the abilities.

The current seven-room world converges well before eight rounds. A future world
with nine or more sequential upgrade gates can still be changing when the loop
ends. The function then continues and returns the last partial report without
saying it stopped early. That is the failure to fix.

### Required behavior

Solve until either:

- no new thing is reachable; or
- the newly reached things do not change the abilities used by the next
  analysis.

Keep a finite safety bound, but derive it from the world rather than a magic
number.

`taken` only grows, and every continuing round must add at least one thing.
There are `_things.size()` total things. Therefore at most
`_things.size() + 1` analyses are needed:

- up to one analysis per newly discovered thing in the worst case; and
- one final analysis with the last upgrade applied, which finds no new thing
  and proves convergence.

### Suggested implementation shape

In `src/world/reach_graph.gd`:

- Remove `MAX_ROUNDS`.
- Introduce a local bound such as:

```gdscript
var max_rounds := _things.size() + 1
var converged := false
for round in max_rounds:
    ...
```

- Preserve the existing round numbers stored in `taken`, `room_round`, and
  `ledge_round`; `_needs()` depends on them.
- After collecting `fresh`, compute the next abilities once and compare them
  with the abilities used for the current analysis.
- Set `converged = true` before breaking for either normal stop condition.
- If the loop exhausts without convergence, append a clear validator error to
  the report. Example:

```text
Progression search did not converge after N rounds for N things
```

That error should be practically unreachable if the monotonic invariant holds.
It exists so a future code change cannot turn the safety bound into another
silent partial result.

- Always restore `abilities = base` before returning, including the
  non-convergence path.
- Preserve trap collection and the existing `needs` calculation.
- Do not change token ordering, the three-token carry limitation, machine
  ordering, Imprint search behavior, or input sampling in this work.

Before finalizing the loop, reason through these cases and cover them in tests:

- zero things;
- things reachable in the first analysis but granting no ability;
- one pickup that opens a later room;
- several pickups reachable in the same round;
- more than eight sequential ability-changing rounds;
- all things collected on the last possible discovery round;
- a self-gated pickup that never becomes reachable.

### Regression test

Add a test to `tests/imprint_solver_test.gd`, near `_progression()`, that needs
more than eight ability-changing solves before its final destination becomes
reachable.

Prefer a real in-memory world built through `RoomParser` and `ReachGraph`, like
the existing tests. A suitable structure is:

- the player begins with no Imprint;
- pickup 1 unlocks Imprint;
- each later reachable section contains one `imprint_width` or
  `imprint_duration` pickup;
- the next section's geometry requires the new value;
- use at least nine sequential upgrades before the final room or final pickup;
- assert the final room/pickup is reached;
- assert its `report.needs` entry contains the expected earlier IDs;
- assert `report.errors` is empty;
- assert `ReachGraph.solve()` restores the starting `Abilities`.

Keep the fixture as small as possible. Reuse or extend the string-room helpers
already at the bottom of `tests/imprint_solver_test.gd`. Avoid adding this
scenario to the real `data/rooms/` world.

If a nine-gate real geometry fixture is too slow or too brittle, a narrow test
subclass/fake analysis may exercise the solve loop, but only as a fallback.
Such a test must still use real `EntityDef` upgrades and the real `_with()`
behavior; it must not simply test `_things.size() + 1` as arithmetic.

The test is complete only after this mutation check:

1. Restore `MAX_ROUNDS := 8` and the old fixed loop temporarily.
2. Run `imprint_solver_test.gd`.
3. Confirm the new assertion fails because the last gate is not reached.
4. Restore the dynamic loop and confirm it passes.

Also run the existing `_progression()`, `_machines()`, and full-world
validation checks unchanged. The current world's reported `needs` sets should
not change.

### Documentation

Update `docs/design/game-design.md` in both relevant descriptions:

- **Checking rooms / What a room needs:** say the solve repeats to a fixpoint,
  bounded by the finite number of things in the world, rather than implying an
  arbitrary number of rounds.
- **Implementation reference:** remove the `MAX_ROUNDS = 8` statement and
  describe the `_things.size() + 1` safety bound and explicit failure on
  non-convergence.

Do not claim that this fixes the separately documented solver limitations:

- token carry order is not modeled;
- blocked doors are not walls during chained falls;
- mid-air Imprint placement is not modeled;
- two Imprint platforms in a row are not modeled;
- jump inputs are sampled rather than exhaustive.

Those are out of scope.

## Verification sequence

During development, use focused tests first:

```sh
godot --headless --path . --import
godot --headless --path . --script tests/imprint_solver_test.gd
godot --headless --path . --script tests/cache_test.gd
./tools/validate.sh --no-cache
./tools/validate.sh
```

Confirm:

- `IMPRINTSOLVER pass`
- `CACHE pass`
- cached and uncached validator answers agree;
- an uncached run populates no cache through the `--no-cache` path;
- a normal validation still reports cache statistics;
- changing `reach_graph.gd` invalidates the old solver cache as expected.

Then run the new complete command:

```sh
./tools/check.sh
```

Finally, on the user's machine or through a local agent:

```sh
./tools/serve.sh
```

Play the routes affected by the current change. The solver-loop change is
offline validator behavior and does not change runtime gameplay, so this
playthrough is primarily a regression check that the freshly built release
still behaves as before.

## Acceptance criteria

- `tools/check.sh` is executable and succeeds from the repository root.
- It runs exactly all 16 current `*_test.gd` scripts.
- It validates the whole world with `--no-cache`.
- It produces and checks a release web build in `build/web/`.
- It stops on the first failed test/check and prints a final pass line only on
  complete success.
- `ReachGraph.solve()` has no fixed eight-round ceiling.
- The solve loop has a finite bound derived from the number of progression
  things and an explicit non-convergence error.
- A regression test requires more than eight sequential progression rounds
  and fails under the old fixed loop.
- Existing solver, cache, and world-validation output remains correct.
- `README.md`, `AGENTS.md`, and `docs/design/game-design.md` describe the new
  command and solve behavior accurately.
- No generated `build/` files are committed.
- No CI, browser automation framework, audio/VFX infrastructure, powerup
  framework, token-state search, room-format change, save-format change, or
  runtime optimization is included.

## Suggested commits

1. `Tools: add one complete local check command`
   - `tools/check.sh`
   - `README.md`
   - `AGENTS.md`
2. `Validator: solve progression to a finite fixpoint`
   - `src/world/reach_graph.gd`
   - `tests/imprint_solver_test.gd`
   - `docs/design/game-design.md`

The pull request should explain:

- automation supplements the owner's browser playthrough;
- why the old eight-round cap could return a partial result;
- why `_things.size() + 1` is a sufficient finite bound;
- which mutation checks were performed;
- the full `tools/check.sh` result;
- that runtime gameplay was unchanged.
