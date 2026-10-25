# Handoff: Imprint lockout, 1.5 s duration, dev-only cooldown

> **Status: built on `game-tweaks`.** This is the spec it was built from; the
> design doc, README and code are now the record. Two things differ from the
> text below: the dev panel's `_nudge` needed **no** rounding change (Godot's
> `str()` already prints `0.30000000000000004` as `0.3`), and `SPARE_TICKS` stayed
> at 40 because the validator passed every room at 1.5 s.

Branch: `game-tweaks`, cut from `main` at `ac82369` (PR #30). One pull request.
This replaces the previous handoff (the `check.sh` and solver-loop plan), which
is finished and merged.

## Purpose

Imprint today lets a player click again and again: each click **replaces** the
oldest platform, so they can keep a platform alive for ever and walk around any
puzzle meant to fit in a platform's life. Change three things:

1. The starting Imprint duration is **1.5 s** (it is 2.5 s now).
2. **No replacing.** While a platform stands, no other can be placed. The next
   one is allowed only after the live one has **broken**.
3. A **cooldown** that starts when a platform breaks on time, adjustable in the
   F2 dev panel. **Its default is 0** (off in real play). The user will try 0.2 s
   through dev tools and may decide against a cooldown, so it must be easy to
   tune and easy to leave at 0.

The rule must stay true for every later feature. It is already written into
`docs/design/game-design.md` and `AGENTS.md` (see "State of the docs" below).

## Decisions the user made (do not re-litigate)

- The cooldown starts when a platform **breaks on time**. Leaving the room,
  dying, warping and a dev-panel Apply clear both the platforms and the cooldown.
- The cooldown **defaults to 0**. It is an ability stat, so it is saved, goes
  into dev loadouts and gets a stepper in the generated panel.
- `imprint_max_active` stays (default 1, still upgradeable, no room awards it).
  At the limit a click is **refused**, never a replacement.
- The cooldown also gets a `data/upgrades.json` entry of a new **`min`** kind
  (lower is better), so a pickup could shorten it later. No room awards it.
- **Old saves are left alone.** A save that stores 2.5 keeps 2.5. Only new
  games and new loadouts get 1.5. No `Save.VERSION` bump.
- Reuse the existing look for "you cannot place here": the small **×** cursor.
  No new visuals. Report this as a judgement in the PR.

## Read first

1. `AGENTS.md` (commands, dev-tools requirement), `README.md` ("What the code
   keeps true", Standards, Recipes).
2. `docs/design/game-design.md`: the **Imprint** section, **Implementation
   reference → Imprint in play** and **The solver**, **Decision log**, and the
   Guardrails. The "decided, not built" text for this work is already in there.
3. Code: `src/imprint/imprint_tool.gd`, `imprint_rules.gd`,
   `imprint_platform.gd`, `src/core/abilities.gd`, `src/core/upgrades.gd`,
   `data/upgrades.json`, `src/world/imprint_search.gd`, `src/dev/dev_catalog.gd`,
   `src/dev/dev_session.gd`, `src/ui/dev_panel.gd`.

Work rules: branch `game-tweaks` (it exists and tracks `origin/main`), do not
push to `main`, run `tools/check.sh` before the PR, one PR, called by its number.
Do not playtest in a cloud agent. Never build a commit message with a heredoc:
write it to `.git/COMMIT_MSG_DRAFT` and use `git commit -F` (user's global rule).
Commit trailers: use the attribution lines the session gives you.

## State of the docs on the branch when you start

Uncommitted edits (commit them with your work) already exist in:

- `docs/design/game-design.md`: a status-table row, the "Decided, not built
  yet" bullet and "Why" bullet under Imprint → Placing, the changed "What it is
  for" bullet, a Decision-log block "Imprint lockout (decided on `game-tweaks`,
  not yet built)", and a paragraph "The Imprint rule every Imprint-related
  feature must keep" at the end of Guardrails.
- `AGENTS.md`: a bullet under "Working on the repo" pointing at that rule.

When the work is built, **you must rewrite those passages as built fact**:
change the status row to Built, delete "Decided, not built yet" and the
"Until it is built, the next bullet..." sentence, delete the old replace
description, and retitle the Decision-log block (drop "not yet built"). Keep the
guardrail paragraph and the AGENTS.md bullet unchanged: they are permanent.

## Part 1: abilities and upgrades

### `src/core/abilities.gd`

- `STATS` gets `"imprint_cooldown"`:
  `["imprint_unlocked", "imprint_width", "imprint_duration", "imprint_max_active", "imprint_cooldown", "imprint_effects"]`
- `var imprint_duration := 1.5`
- New field, after `imprint_max_active`:
  ```gdscript
  ## Seconds after a platform breaks before another may be placed. 0 is off.
  var imprint_cooldown := 0.0
  ```
  Keep the `0.0` float literal: `Upgrades.check` and `parse_value` read the stat's
  type from the default value.
- `to_dict`: `"imprint_cooldown": imprint_cooldown,`
- `from_dict`: `out.imprint_cooldown = float(data.get("imprint_cooldown", out.imprint_cooldown))`
- `apply()`: add a branch for the new `"min"` kind, before the final `max`
  logic:
  ```gdscript
  if upgrade["kind"] == "min":
  	var current: Variant = get(stat)
  	if value >= current:
  		return false
  	set(stat, value)
  	return true
  ```
  Update the doc comment above `apply` to say `"min"` keeps the smaller value.
- `describe()`: append `", %.1f s cooldown"` only when `imprint_cooldown > 0.0`.

### `src/core/upgrades.gd`

- `KINDS` becomes `["unlock", "max", "min", "add"]`; update the header comment
  (`"min" lowers a number`). `check` and `parse_value` already treat any kind
  other than `unlock` and `add` as numeric, so nothing else changes.

### `data/upgrades.json`

Add after `imprint_max_active`:

```json
  "imprint_cooldown": {
    "name": "Imprint cooldown",
    "stat": "imprint_cooldown",
    "kind": "min",
    "dev": {
      "type": "float",
      "min": 0,
      "max": 1000000,
      "step": 0.1,
      "unit": "seconds"
    }
  },
```

`DevCatalog.controls` generates the panel row, validation (`check_value`
enforces `min`/`max`) and loadout coverage from this metadata. No widget code is
needed, except the rounding fix below.

### `src/ui/dev_panel.gd` (`_nudge`, around line 273)

Float steps of 0.1 accumulate error (`0.1 * 3` prints `0.30000000000000004`).
Change the last line of `_nudge` to:

```gdscript
edit.text = str(int(value)) if control["type"] == "int" else str(snappedf(value, 0.001))
```

This leaves the existing 0.5 duration step unchanged.

### Saves and loadouts

- No `Save.VERSION` bump: `from_dict` falls back to the default for the missing
  field (README rule 7). Old saves keep their stored `imprint_duration`.
- `DevCatalog.reconcile` already fills missing abilities from
  `Abilities.new().to_dict()`, so an old named loadout picks up cooldown 0 and
  keeps its own stored duration. `validate` requires every control's stat, so
  confirm `reconcile` of an old loadout (without `imprint_cooldown`) validates:
  `draft = defaults()` supplies it.

## Part 2: the runtime rule

### `src/imprint/imprint_rules.gd`

Add a pure static function (no autoload, no nodes):

```gdscript
## Why no platform may be placed right now, or an empty string if one may.
## `active` platforms stand, `max_active` is the limit, and `cooldown_left` is
## the seconds still to wait after the last one broke. Reasons: limit, cooldown.
static func blocked(active: int, max_active: int, cooldown_left: float) -> String:
	if active >= maxi(max_active, 1):
		return "limit"
	if cooldown_left > 0.0:
		return "cooldown"
	return ""
```

Also append `limit, cooldown` context to the doc comment of `check` pointing at
`blocked` (check stays purely about *where*).

### `src/imprint/imprint_tool.gd`

- Add `var cooldown_left := 0.0` beside `platforms`, with a `##` comment.
- `place()`:
  ```gdscript
  if not is_active():
  	return false
  if not ImprintRules.blocked(platforms.size(), GameState.abilities.imprint_max_active, cooldown_left).is_empty():
  	return false
  ... existing room/cell/width ...
  var reason := ImprintRules.check(room.info, cell, width, _local(_player.body_rect(), room), _local_all(platforms, room))
  if not reason.is_empty():
  	return false
  ```
  **Delete** `var survivors := _survivors()`, the `while platforms.size() > survivors.size()` replace loop, and
  the whole `_survivors()` function. Every live platform now counts for overlap
  (`others`), because none is ever removed by a click.
- `_break(platform, _replaced)`: remove the unused second parameter and update
  its two callers (`clear`, `_physics_process`).
- `_physics_process(delta)` (still skipped while the world is busy, so the
  cooldown pauses with ageing; leave that early return):
  ```gdscript
  cooldown_left = maxf(cooldown_left - delta, 0.0)
  var broke := false
  for platform in platforms.duplicate():
  	platform.age += delta
  	if platform.expired():
  		_break(platform)
  		platforms.erase(platform)
  		broke = true
  		cooldown_left = GameState.abilities.imprint_cooldown
  ```
  The decrement comes first so the tick a platform breaks does not shave the new
  cooldown. A second platform breaking later restarts it (only possible with
  `imprint_max_active` above 1).
- `clear(effects)`: also set `cooldown_left = 0.0`. This is the single path for
  leaving a room, dying, warping (`World` calls it) and a dev Apply
  (`DevSession.apply` calls `world.imprint.clear(false)`). Retries rebuild the
  whole world, so a new `ImprintTool` starts at 0.
- `_update_preview`:
  - Compute `var blocked := ImprintRules.blocked(platforms.size(), GameState.abilities.imprint_max_active, cooldown_left)`.
  - Add `cooldown_left > 0.0` to the cache `key` string, so the × lifts when the
    cooldown ends (the key already contains `platforms.size()`).
  - If `blocked` is not empty: `_reason = blocked; _state = UNAVAILABLE; return`.
    This is checked before the `ImprintRules.check` call, so the cursor shows
    the × anywhere while locked out.
  - Replace both `_survivors()` uses with `platforms`.
- `_draw_preview` needs no change: `UNAVAILABLE` already draws the ×.
- The doc comment at the top of the file and `place()` should say a click is
  refused while a platform stands or the cooldown runs.

Not changed: `ImprintPlatform` (the clock, dashes and blink scale with
`lifetime`; at 1.5 s the width-2 platform has 4 dashes, one every 0.375 s, and
the blink lasts the last dash's share, 0.375 s). `World` (busy states already
stop `_physics_process`).

## Part 3: the solver (required, or validation fails at 1.5 s)

### Why it is needed

`ImprintSearch._leg_limit()` gives each of two jumps
`clampi((life_ticks - SPARE_TICKS) / 2, MIN_LEG, 180)`. At 1.5 s that is
`(90 - 40) / 2 = 25`, clamped up to `MIN_LEG` 30, the **same** as the 1.0 s case
(`(60 - 40) / 2 = 10 → 30`). The existing assertion in
`imprint_solver_test._gate` ("a platform that lasts one second is not enough")
would then be hit by the new default, and rooms 5 and 6 may stop validating.

### What to model

The platform has to exist while the player **lands on it** and is still on it
until they push off. After they leave it, they no longer need it. So:

- The jump **onto** the platform gets the platform's life less the time to
  stand and push off.
- The jump **off** it is not limited by the platform's life (an ordinary
  ledge's 180-tick limit).

### `src/world/imprint_search.gd`

- Replace `_leg_limit()` with:
  ```gdscript
  ## How many ticks the jump onto a platform may run: the platform's life, less
  ## SPARE_TICKS to stand on it and push off. Zero means it is gone first.
  func _land_limit() -> int:
  	var life := int(_graph.abilities.imprint_duration * 60.0)
  	return clampi(life - SPARE_TICKS, 0, 180)
  ```
- In `expand`: `var limit := _land_limit()`; if `limit <= 0` return `out`
  (before any simulation). Use `limit` for the arc scan
  (`range(1, mini(arc.path.size(), limit + 1))`) and for `_lands_on(...)`, as now.
- For the leg off the platform use the ordinary frame limit: add
  `const LEG_TICKS := 180` (matches `ReachGraph.frame_limit`; check that name in
  `reach_graph.gd` and use its constant if one exists) and call
  `_leg_of(info, geo, candidate.cell, width, LEG_TICKS)`. Keep `_leg_key`
  unchanged (it still includes the limit argument).
- Delete `MIN_LEG`. Update the header and constant comments: `SPARE_TICKS` is
  now "ticks to stand on the platform and push off".
- `imprint_search.gd` is in `SolverCache.SOLVER_FILES`, so the cache
  fingerprint changes by itself. Do not add a manual invalidation.

### Fallback ladder (decide by running, report every step)

1. Run `tools/validate.sh --no-cache`. It must exit 0 and print the **same
   `needs` lines** as `main`: record `main`'s output first
   (`git stash; tools/validate.sh --no-cache`, or read it from a fresh worktree
   of `ac82369`).
2. If a pit room fails (rooms 5 and 6 are the likely ones; flight across room
   5's 16-cell pit takes about 50 ticks), lower `SPARE_TICKS` from 40 to 30
   (land limit 60) and rerun. Report this as a judgement.
3. If it still fails, **stop and ask the user** whether to change the room or
   the duration. Do not edit rooms, do not lower `SPARE_TICKS` below 30.

### No lockout model in the solver

The solver puts down one platform per path, never two in a row, and none from a
moving platform, then continues from ledges that exist afterwards. Waiting for a
platform to break and a cooldown to pass is always possible on a real ledge, so
the lockout and the cooldown change nothing it computes. Say exactly this in the
design doc (see Part 5), because it is the reason the guardrail exists: a
feature that makes waiting costly breaks that argument.

## Part 4: tests

Mutation-check every new or changed check (README Standards): break the thing
on purpose, see the test fail, put it back, and list the mutants in the PR.

Existing assertions that depend on the old numbers or behaviour (found with
`grep -rn -E "2\.5|imprint_duration|_survivors|max_active|lifetime" tests src`):

- `tests/save_test.gd:31`: "the starting abilities are width 2, 2.5 s, ..." →
  1.5 s, plus `imprint_cooldown == 0.0`, and fix the label.
- `tests/imprint_test.gd:139-179`: the clock tests use ages 0.5/1.5/2.5/3.5 and
  a "starting platform lasts 2.5 seconds" block, with `start.age = 2.5` at line
  178. Rework them for 1.5 s: lines gone per 0.375 s, blink for the last 0.375 s,
  expired at 1.5. Read the whole block (lines 130-190) before editing, keep
  every property being tested, and recompute the expected line counts.
- `tests/dev_catalog_test.gd:49`: `== 2.5` → `== Abilities.new().imprint_duration`.
  The loop at lines 21-35 round-trips every `Abilities` property automatically,
  so it covers `imprint_cooldown` once registered; confirm it ran for it.
- `tests/imprint_play_test.gd`: see below.
- `tests/imprint_solver_test.gd:43`: keep "one second is not enough" if it still
  fails to cross (land limit 20 ticks, it should). If it does not, lower the
  duration to the largest value that still cannot cross and say so.
- `tests/hazard_test.gd`, `tests/dev_session_test.gd`, `tests/dev_ui_test.gd`,
  `tests/reach_test.gd`: they set durations explicitly, so they probably need no
  change, but read each platform-placing step: any test that places twice in a
  row relied on replacing and must clear first (`tool.clear(false)` followed by
  `tool.sync_solids()`).

### New and rewritten tests

`tests/imprint_test.gd` (pure):
- `ImprintRules.blocked(0, 1, 0.0) == ""`, `(1, 1, 0.0) == "limit"`,
  `(0, 1, 0.2) == "cooldown"`, `(1, 1, 0.2) == "limit"` (limit wins),
  `(1, 2, 0.0) == ""`, `(2, 2, 0.0) == "limit"`, and `max_active` of 0 behaves as 1.

`tests/imprint_play_test.gd` (scene, room 5; currently lines 62-83 test
replacement and lines 77-78 clear `platforms` directly):
- The "a second click replaces the first at once" check becomes: a second
  `place()` while one stands returns false, `platforms.size() == 1`, the first
  platform's rect is unchanged, and the preview reason is `"limit"` with state
  `unavailable`.
- Clicking five times in a row with the action (`Input.parse_input_event`) still
  leaves one platform, whose `age` has not been reset.
- After the platform breaks on time (set `lifetime = 0.5` as the existing test
  does), with cooldown 0, `place()` works on the very next call.
- Set `state.abilities.imprint_cooldown = 0.2`. After a break `place()` is refused,
  the preview reason is `"cooldown"`, `tool.cooldown_left` is about 0.2, and
  after about 12-14 physics frames `place()` works. Also check the cooldown does
  not run while the world is busy if that is easy to arrange; otherwise note it
  as unchecked.
- `state.abilities.imprint_max_active = 2`: two platforms stand, a third is
  refused with `"limit"`. Restore afterwards.
- `warp_to` and a death both leave `cooldown_left == 0.0` and no platforms (set
  a cooldown first so a mutant that skips the reset fails).
- Replace the "Replaced at once" block (lines 74-83) with the above; where the
  old code cleared `tool.platforms` directly, use `tool.clear(false)` then
  `tool.sync_solids()` so `player.solids` stays in step.
- Restore `imprint_cooldown`, `imprint_max_active`, `imprint_duration` and width
  to `Abilities.new()` values at the end.

`tests/save_test.gd`: round trip of `imprint_cooldown`; `apply` of the `min`
kind (a lower value is taken, a higher or equal one is not; `true` / `false`
return values); a save dict without `imprint_cooldown` loads as 0; a save dict
with `imprint_duration: 2.5` still loads as 2.5 (the old-save decision).

`tests/dev_catalog_test.gd`: `imprint_cooldown` validates at 0, 0.2 and 5; is
rejected at -0.1, NAN, INF, "0.2" and `true`; an old loadout without it
reconciles and validates.

`tests/dev_session_test.gd`: applying `{"abilities": {"imprint_cooldown": 0.2}}`
clears live platforms and `cooldown_left`; retry keeps the latest cooldown in
`state.abilities` (mirror the existing duration assertions around lines
51 and 83).

`tests/dev_ui_test.gd`: the generated panel has an `imprint_cooldown` field;
typing `0.2` and Apply sets the ability; the `+` button from 0 gives `0.1`,
three presses give `0.3` (not `0.30000000000000004`), and `-` stops at 0.

`tests/imprint_solver_test.gd`: the default `Abilities` (1.5 s) crosses the
12-cell pit; 1.0 s does not; a duration of 0.5 s makes `expand` return nothing
(land limit 0) without error.

`tests/entity_test.gd`/`reach_test.gd`: add a pickup line with
`upgrade=imprint_cooldown value=0.5` and check it parses (`kind=min` is numeric);
`value=long` is the same error as for duration.

Mutants to try (minimum): drop the `blocked` check from `place`; restore the
replace loop; let `clear` skip the `cooldown_left` reset; start the cooldown on
placement instead of on the break; `>=` → `>` in `min` apply; make `blocked`
ignore `max_active`; revert `_land_limit` to halving; take `min` out of `KINDS`.

## Part 5: docs (same PR)

`docs/design/game-design.md`:
- Status table: the new row goes to **Built**; the "Imprint width, duration and
  multiple active platforms" row stays.
- Imprint intro status paragraph, the **Placing** bullets and the **What it is
  for** bullet: rewrite as built fact (see "State of the docs").
- "A legal placement lasts `duration` seconds, 2.5 at the start. ... four ...
  so at 2.5 seconds one goes every 0.625 seconds": → 1.5 and 0.375.
- **Upgrades** table: duration starts at 1.5 seconds; add a row "Cooldown | 0
  seconds (off) | a pickup could lower it; none exists, and it is tried in dev
  tools".
- "The starting values are the defaults in `Abilities`": width 2, duration 1.5
  seconds, one at a time, cooldown 0, no behaviour, locked.
- **Checking rooms → Imprint in the solver**: replace the bullet "A platform
  lives `imprint_duration` seconds, so each of the two jumps is cut to half..."
  with the new model (jump onto it within life less `SPARE_TICKS`; the jump off
  is an ordinary ledge's), and add the "no lockout model needed" paragraph from
  Part 3, including that a feature making waiting costly breaks the argument.
- **Implementation reference → Imprint in play**: `place` refuses on
  `ImprintRules.blocked` (limit, cooldown) then `ImprintRules.check`; no
  replacing; `cooldown_left`, when it starts, what clears it, that it pauses
  while busy; the preview key now includes the cooldown; the reasons list gains
  `limit` and `cooldown`.
- **Implementation reference → solver**, the `ImprintSearch` bullet: "A leg's
  tick limit is `clamp((duration × 60 − SPARE_TICKS) / 2, ...)` (55 ticks at
  2.5 s)" → the new `_land_limit` (50 ticks at 1.5 s) and `LEG_TICKS`.
- **Dev playtesting** section and the **Dev implementation** note: the panel now
  edits the cooldown too.
- **Decision log**: the block is already written; make it say "Built" and add
  anything you decided (such as a lowered `SPARE_TICKS`, and the numbers).
  Update the 2.5 s line under "Imprint's look and timing" with "then 1.5 s".
- **Not decided**: the "save from before a change to a starting number" bullet
  now cites 2.5 → 1.5 as well; add "whether the cooldown should stay at 0, and
  what value, to be decided after playtesting".

`README.md`: Dev playtesting → Player bullet adds cooldown; the
`imprint_play_test` table row lists refused-while-standing and the cooldown;
Recipes → "A new upgrade" mentions the `min` kind; "What the code keeps true" gets
a rule 11, "Imprint is never replaced or refreshed by another click" (one
sentence, pointing at the design doc's guardrail); the code-layout row for
`src/core/` is unchanged.

`AGENTS.md`: keep the added bullet; add `imprint_cooldown` to the list of
`upgrade` keys in the Room files section.

`docs/testing-checklist.md` (new unplayed items, in a new "Imprint lockout"
section): spamming clicks leaves one platform and its clock does not restart;
the × shows while one stands; 1.5 s is enough for room 5's pit both ways and for
room 6's wall; with the cooldown at 0.2 in F2 the × returns briefly after each
break and feels fair or not; the Imprint dashes and blink still read at 1.5 s.
Also edit line 9 ("the 2.5 second Imprint of PR #21") only by adding that the
duration is now 1.5 s: do not tick anything as played.

## Verification

Order:

1. `godot --headless --path . --import`
2. Focused: `tests/imprint_test.gd`, `imprint_play_test.gd`, `imprint_solver_test.gd`,
   `save_test.gd`, `dev_catalog_test.gd`, `dev_session_test.gd`, `dev_ui_test.gd`,
   `entity_test.gd`, `reach_test.gd`, `cache_test.gd`, `hazard_test.gd`
3. `tools/validate.sh --no-cache`: exit 0, the same `needs` lines as `main`.
   Then `tools/validate.sh` (cached) agrees.
4. `tools/check.sh`: the complete gate; it leaves `build/web/`.
5. `tools/serve.sh` for the user's playthrough at http://localhost:8060. The
   owner expects the web build to be rebuilt and served after each piece of work.

The user plays: room 5's pit both ways and room 6's wall at 1.5 s; spam-clicking
no longer extends a platform; `?dev=1&room=5`, F2, set the cooldown to 0.2,
Apply, and the × returns briefly after each break.

## Acceptance criteria

- A click while a platform stands (or the cooldown runs) places nothing, with a
  `limit` or `cooldown` reason and the × cursor.
- Default duration is 1.5 s; default cooldown is 0; old saves keep their value.
- The dev panel edits the cooldown (steps of 0.1, no float noise), the value
  survives retry and named loadouts, and applying it clears live platforms.
- `tools/validate.sh` passes with unchanged `needs` lines; any `SPARE_TICKS`
  change is reported.
- `tools/check.sh` ends in its pass line.
- Docs updated as listed; the design-doc "not built" language is gone.
- No new rooms, no room edits, no save-version change, no new test files (the
  README's "21 tests" stays true), no solver cache edits by hand.

## Suggested commits

1. `Imprint: no replacing, 1.5 s duration, and a solver leg model for it`
   (tool, rules, abilities duration, solver, tests, docs)
2. `Imprint: add a cooldown stat that is off by default, with dev controls`
   (`imprint_cooldown`, `min` kind, panel rounding, tests, docs)

The PR describes: why replacing was removed; the default duration and cooldown;
the solver's new time budget and any `SPARE_TICKS` judgement; the mutants tried;
the full `tools/check.sh` result; and what was **not** played (all of the
checklist's new section).
