# Handoff: shrinking Imprint, dotted border, default width 3, Classic dev switch

_Updated 2026-10-25. Written as a build spec: implement exactly as written, and ask before deviating._

> **Status: built, not yet played by a person.** Implemented on branch
> `claude/imprint-shrink-feature-lu7gcy` (PR #33), to this spec, with the
> judgement calls listed in that pull request. `docs/design/game-design.md` now
> describes the shrinking behaviour. The previous handoff (Imprint lockout, 1.5 s,
> dev-only cooldown) was built and merged as PR #31.

## Goal

The user's words: "instead of a timer that is present on the platform, the platform
itself gets smaller each interval, one block at a time. so the last interval of the
countdown the imprint size is just 1 block." The timing is unchanged: an Imprint
lasts `imprint_duration` (1.5 s by default), and one block disappears each interval
of that countdown. The `imprint_width` setting becomes the **starting** size.

Because the countdown dashes no longer mean anything, a placed platform is drawn
with a **dotted border** so the player can tell what they placed. The current
behaviour (full width for the whole life, the dash clock, the last-dash blink) is
kept behind a **dev checkbox** so the user can compare both at any time. The new
behaviour is the default.

## Branch

Cut `imprint-shrink` from the latest `origin/main` (`git fetch origin && git switch -c imprint-shrink origin/main`). One pull request. Merge with the `merge-pr-admin` skill when the user asks.

Uncommitted: nothing. This file arrives on `main` by its own small PR.

## Decisions the user made (do not re-litigate)

| Question | Decision |
| --- | --- |
| Shrink order | From the ends toward the middle, alternating, **starting on the left**. The **default width becomes 3**, so the exact middle block is the last one. In general the last block is index `width / 2` (integer division): width 2 -> the right block, width 4 -> the third, width 5 -> the middle. |
| Interval | **Life / starting width.** At width 3 and 1.5 s, one block goes every 0.5 s: 3 blocks until 0.5 s, 2 until 1.0 s, 1 until 1.5 s. The total time never changes with width. |
| Warning | Only the **next block to go blinks**, for the last 0.25 s before it goes (capped, see `warn_time`). Its collision stays until it goes. |
| Look | A white block with a **1 px black dotted border drawn 1 px inside its edge**, which follows the platform as it shrinks. No dashes. |
| Dev switch | A **session switch** on the F2 Player tab, "Classic Imprint (no shrinking)", off by default. It works like door bypass: it survives retries, is **not** saved, **not** in loadouts, and End playtest or a fresh boot resets it. Normal play always shrinks. |
| Solver | Counts **only the last block** as footing. That block stands for the whole life, so a route the solver accepts does not depend on an outer block still being there. |
| Old saves | **Left alone.** A save that stores width 2 keeps 2. Only new games start at 3. (Same rule as the duration in PR #31.) |
| Cooldown | Unchanged from PR #31 (default 0, starts when the platform finally breaks). |

### Discrepancies found while planning (all settled above, listed so nobody reopens them)

- "One block per interval" cannot reuse today's 0.375 s interval: that is per **dash**, and a block has two dashes, so a 3-block platform would be gone in 1.1 s. The interval is life / starting width instead.
- Under the last-block solver model, a wider starting width never makes a room easier **on paper** (the validator ignores outer blocks). It does help in play. Accepted.
- `imprint_width value=3` pickups in tests now give nothing at the new default. They still parse and are still reached, so those tests are unaffected; confirm each when you run them.
- When `imprint_max_active` is 2 or more, the cells of a shrinking platform are free for a second platform as soon as they go. That is fine: nothing is replaced or refreshed.

## The rule this must not break

PR #31 added a permanent guardrail ("The Imprint rule every Imprint-related feature must keep", design doc, Guardrails; and the Imprint bullet in `AGENTS.md`): **an Imprint is never replaced, refreshed or extended by another click.** Shrinking never extends a life; it only removes footing earlier than before. Keep it that way, in the runtime and in the solver.

## What changes, file by file

Line numbers are from `main` at `f13f8fc`.

### 1. `src/core/abilities.gd`

`imprint_width := 3` (it is 2 now). Nothing else: `STATS`, `to_dict`, `from_dict`, `apply` and `describe` need no change, and there is **no `Save.VERSION` bump** (README rule 7: a missing field falls back to its default; a stored 2 stays 2). `data/upgrades.json` is unchanged (`imprint_width`: kind `max`, dev int, min 1).

### 2. `src/imprint/imprint_platform.gd` (the heart of the change)

Today (70 lines): `rect`, `lifetime`, `age`, `expired()`, `blinked_off()`, `blink_time()`, `lines_left()`, `line_rects()`, `draw()`, `_line_xs()`. **Keep all of the dash code** for the Classic mode; it is used only when `shrinks` is false.

Add constants and fields:

```gdscript
## The block that goes next blinks for this long before it goes.
const WARN_TIME := 0.25

## In world pixels. `rect` is the footing right now: the whole platform when new,
## then the blocks that still stand. `full_rect` is what was placed.
var rect := Rect2()
var full_rect := Rect2()
var lifetime := 4.0
var age := 0.0
## How many blocks it was placed with, and whether it loses them. A platform that
## does not shrink is the Classic dev mode: full width until it breaks, with a
## dash clock.
var cells := 1
var shrinks := true


func _init(world_rect: Rect2, seconds: float, shrinking := true) -> void:
	rect = world_rect
	full_rect = world_rect
	lifetime = seconds
	shrinks = shrinking
	cells = maxi(roundi(world_rect.size.x / float(Grid.CELL)), 1)
```

Every existing reader keeps using `.rect` (`ImprintTool.sync_solids`, `_local_all`, the preview's `rects`, tests), so **`rect` must always be the current footing**.

Pure helpers (all derived from `age` and `lifetime`, so they are unit-testable with no scene):

```gdscript
## How many blocks still stand: one is lost in each equal share of the life.
func blocks_left() -> int:
	if not shrinks:
		return cells
	return clampi(ceili(float(cells) * (lifetime - age) / lifetime), 0, cells)


## The cells that have gone, counted from the left and from the right, for
## `removed` blocks gone. Left first, then right, then left again, so the cell
## that lasts is `cells / 2`.
func _left_gone(removed: int) -> int:
	return (removed + 1) / 2


func _right_gone(removed: int) -> int:
	return removed / 2


## The index (0 = leftmost) of the block that goes next, or -1 if none is left.
func next_cell() -> int:
	var left := blocks_left()
	if left <= 0 or not shrinks:
		return -1
	var removed := cells - left
	return _left_gone(removed) if removed % 2 == 0 else cells - 1 - _right_gone(removed)


## Seconds until the next block goes.
func time_to_next() -> float:
	var removed := cells - blocks_left()
	return lifetime * float(removed + 1) / float(cells) - age


## How long the next block blinks: WARN_TIME, but never more than half a share,
## so a platform with a very short share is not blinking all the time.
func warn_time() -> float:
	return minf(WARN_TIME, lifetime / float(cells) * 0.5)


## Whether the block that goes next is blinked off at this moment.
func blinking_off() -> bool:
	return shrinks and next_cell() >= 0 and time_to_next() <= warn_time() and int(age / BLINK_PERIOD) % 2 == 1


## The footing for `left` blocks standing, in world pixels.
func footing(left: int) -> Rect2:
	var removed := cells - left
	var from := _left_gone(removed)
	var cell := float(Grid.CELL)
	return Rect2(full_rect.position.x + float(from) * cell, full_rect.position.y, float(left) * cell, full_rect.size.y)
```

Check the closed forms against the order left, right, left, right, ...: for `removed` blocks gone the left count is `ceil(removed / 2)` and the right count is `floor(removed / 2)`. Width 3: removed 1 -> cells 1..2, removed 2 -> cell 1. Width 4: removed 3 -> cell 2. Width 5: removed 4 -> cell 2. Width 2: removed 1 -> cell 1. Width 1: never shrinks until expiry. (Verified by hand, not yet by a test; the test in section 7 pins it.)

The tool calls this each physics tick, after ageing:

```gdscript
## Brings `rect` in line with `age`. Returns the rects of the blocks that just
## went (empty most ticks), so the caller can shatter them.
func update_footing() -> Array[Rect2]:
	var gone: Array[Rect2] = []
	var left := blocks_left()
	# left == 0 is expiry, which ImprintTool handles with _break (below).
	if not shrinks or left <= 0:
		return gone
	var before := rect
	var after := footing(left)
	if after.size.x >= before.size.x - 0.5:
		return gone
	var cell := float(Grid.CELL)
	var x := before.position.x
	while x < after.position.x - 0.5:
		gone.append(Rect2(x, before.position.y, cell, before.size.y))
		x += cell
	x = after.end.x
	while x < before.end.x - 0.5:
		gone.append(Rect2(x, before.position.y, cell, before.size.y))
		x += cell
	rect = after
	return gone
```

It never returns the last block: its removal is the platform's expiry, which `ImprintTool` already handles with `_break(platform)` at `platform.rect.get_center()` (the last block, because `rect` is the last block by then).

Drawing (`draw(canvas)`): branch on `shrinks`.

- `not shrinks`: today's body, unchanged (`blinked_off()`, white rect, black dashes).
- `shrinks`: the block that blinks off is always an **end** of the footing (the next to go is the leftmost or rightmost standing block), so the drawn area stays one contiguous rect:

```gdscript
func drawn_rect() -> Rect2:
	var shown := rect
	if blinking_off():
		var cell := float(Grid.CELL)
		if (cells - blocks_left()) % 2 == 0:  # an even count gone: the left end goes next
			shown.position.x += cell
		shown.size.x -= cell
	return shown
```

Then draw `shown` white, and a black dotted border one pixel inside it: for every pixel on the perimeter of `shown.grow(-1.0)`, draw it black when `(px - full_rect.position.x + py) % 2 == 0` (parity measured from the placed platform's origin so the dots do not shimmer when it shrinks). `draw_rect(Rect2(x, y, 1, 1), Color.BLACK)` per pixel is fine (the cursor's `_dotted` does the same; see `imprint_tool.gd:236`). If `shown.size.x <= 0` (the last block blinked off) draw nothing. Pixel-aligned: the rect edges are whole multiples of 10 px, so no rounding issue.

Update the class doc comment to say the platform's own width is its clock, and that `shrinks == false` is the Classic dev mode.

### 3. `src/imprint/imprint_tool.gd`

- `place()` (line 87): `platforms.append(ImprintPlatform.new(rect, GameState.abilities.imprint_duration, not DevSession.classic_imprint_active()))`.
- `_physics_process` (lines 110-127). After `platform.age += delta`, in the `else` of the expiry branch:

```gdscript
		var gone := platform.update_footing()
		for block in gone:
			_shatter_at(block.get_center())
			broke = true
```

  Add `_shatter_at(position)` (the body of the existing `_break` taking a position; have `_break(platform)` call it with `platform.rect.get_center()`). Keep the cooldown logic exactly as it is: the cooldown starts when the platform finally expires (`cooldown_left = GameState.abilities.imprint_cooldown`), **not** when a block goes.
- `_update_preview` (line 150) caches on `platforms.size()`; a shrinking platform changes `rect` but not the count. The preview refuses placements that overlap a standing platform via `_local_all(platforms, room)`; with shrinking it will see the shrunk rect, which is correct. Add the **blocks standing** to the cache key so the refusal is recomputed when a block goes: `"%s|...|%d|%d|%s" % [..., platforms.size(), _blocks_standing(), cooldown_left > 0.0]` where `_blocks_standing()` sums `blocks_left()` over `platforms`. (Without it the cursor can show a stale refusal for up to one cell move; mutate this to check the test catches it, or note that no test can.)
- The reach preview (`ImprintReach.can_land_on`, line 168) still treats the platform under the cursor as full width. That is correct for a platform not yet placed; the look does not separate reachable from unreachable today (see `_draw_preview`). No change; mention it in the design doc.

### 4. Dev switch: `src/dev/dev_session.gd`, `src/ui/dev_panel.gd`

`DevSession`:

```gdscript
var classic_imprint := false

## Whether a platform placed now keeps its width. Only in a dev test, so normal
## play can never see the switch.
func classic_imprint_active() -> bool:
	return mode == Mode.DEV_TEST and classic_imprint


func set_classic_imprint(world: Node, on: bool) -> String:
	if mode != Mode.DEV_TEST or replacing or world.is_busy():
		return "Dev tools are not ready."
	classic_imprint = on
	# Platforms of the other kind must not stand beside the new ones.
	world.imprint.clear(false)
	world.imprint.sync_solids()
	return ""
```

Reset `classic_imprint = false` in `configure()` (next to `bypass = false`) and in `_replace()` when `normal` is true (next to `bypass = false`). A retry (`_replace(..., normal=false)`) leaves it as it is, like `bypass`.

`DevPanel`:

- `var _classic: CheckButton` next to `_bypass` and `_retry` (lines 19-20).
- Build it in `_build_player` after the existing buttons, mirroring `_bypass` (lines 296-302): text "Classic Imprint (no shrinking)", `toggled` calls `_report(DevSession.set_classic_imprint(_world, on))` then `_classic.set_pressed_no_signal(DevSession.classic_imprint)`.
- `open_panel` (lines 90-91): add `_classic.set_pressed_no_signal(DevSession.classic_imprint)`.
- `_process` (line 41-45): add `if DevSession.classic_imprint: suffix += " · classic imprint"`.
- It is **not** part of `_draft()`, `_apply()`, `_set_fields()` or named loadouts. Do not add it to `DevCatalog`, `Abilities.STATS` or `data/upgrades.json`: it is a comparison switch, not progression, so `dev_catalog_test` is unaffected. Write down why in the README and the design doc.
- The panel window is 312 x 160 and the dev UI test asserts it fits; the Player tab scrolls (`_page`), so one more row is fine.

### 5. Solver: `src/world/imprint_search.gd`

Principle: placement legality is about the whole platform, but the footing the solver counts on is the **last block**, which stands for the whole life.

- Add a helper:

```gdscript
## The block that stays longest: the middle one (`width / 2` from the left).
func _last_block(cell: Vector2i, width: int) -> Rect2:
	return Grid.cell_rect(Rect2i(Vector2i(cell.x + width / 2, cell.y), Vector2i(1, 1)))
```

- `_collect`, `_near_a_target`, and the `ImprintRules.check` call stay as they are (full width).
- `_lands_on` (lines 149-161): simulate as today with the full platform in `rects`, but the landing must be on the **last block** (replace the `platform.position.x` / `platform.end.x` overlap test with the last block's `position.x` / `end.x`; the `y` test is unchanged). To be sound regardless of when outer blocks go, **also** re-run the same arc with only the last block in `rects` instead of the full platform and require the same landing (`at.distance_to(at_full) < 0.5`). An arc that touches an outer block differs between the two runs and is dropped. The second simulation runs only after the first succeeded, so the extra cost is small; measure it (see Verify).
- Legs (line 87): `var leg := _leg_of(info, geo, Vector2i(candidate.cell.x + width / 2, candidate.cell.y), 1, _graph.frame_limit)`. The pseudo-ledge and its near solids are the one block. `_leg_key` keeps its format, but the stored width is now always 1, so legs are shared across widths.
- `_land_limit()` is unchanged (`life - SPARE_TICKS`): the last block stands for the whole life.
- Rewrite the class doc comment (lines 4-20) and the "What it leaves out" list: add "landing on an outer block while it stands, and walking off onto outer blocks while they stand. Classic mode is not modelled either; it has strictly more footing, so validation is conservative for it."
- `imprint_search.gd` is in `SolverCache.SOLVER_FILES`, so the cache invalidates itself. `cache_test` should confirm.

**Stop point.** If `tools/validate.sh --no-cache` fails any room at width 3 with this model, or `imprint_solver_test` `_gate`, `_barrier` or `_room_six` fail (they stand in for rooms 5 and 6), **stop and report to the user**: the room, the failing line, and the `needs` lines before and after. Do not move platforms, retune `SPARE_TICKS` or `WARN_TIME`, or edit rooms without asking. Last time (PR #31) every room passed at 1.5 s with identical `needs` lines to `main`.

### 6. Tests that assume the old defaults (fix these first)

Run `godot --headless --path . --import`, then each test, and fix what breaks. Known cases, found by reading the code:

- `tests/save_test.gd:31` and `:88`: width 2 -> 3. Keep `Abilities.from_dict({"imprint_width": 2}).imprint_width == 2` as a new check (old save keeps its width).
- `tests/dev_session_test.gd:41`: "fresh state" expects width 2 -> 3. Lines 48 and 53 build `ImprintPlatform.new(Rect2(10, 10, 20, 10), ...)` with the default `shrinking := true`; they only check that Apply clears platforms, so they still pass.
- `tests/imprint_play_test.gd`:
  - The "Time breaks it" block (lines 102-118) puts the player at `Vector2(35, 20)` on a platform at cell (3, 6). At width 3 that platform is x 30..60 and the player stands on its **left block, which now goes at lifetime/3 = 0.167 s**, so "the player stands on it before it breaks" fails. Move the player onto the middle block (x = 45) and keep the rest.
  - Line 126: `rect.size.x == 30.0` was written for `imprint_width = 3` and still holds. Line 128 resets width with a literal `2`; change it to `Abilities.new().imprint_width`.
  - Other rect checks (line 95: `rect.position.x == room.position.x + 100.0`) test the left end, which does not move at placement; fine.
- `tests/imprint_test.gd`: `_platform` (line 88) and `_countdown` (line 134) build platforms with the default `shrinking := true`; pass `false` as the third argument so they keep testing the Classic dash clock. The `_countdown` header comment and docstring ("The dashes are a clock") should say Classic.
- `tests/hazard_test.gd:84-93`: places at cell (14, 15), now 3 wide, over spikes in row 16, with `lifetime = 0.05`. Expected to pass unchanged; run it.
- `tests/cache_test.gd:147`: "the file keeps the legs of both widths apart" asserts widths 2 and 3 in the stored leg keys. Legs are now one block wide, so replace it with "every stored leg is one block wide" (`String(key).get_slice("|", 2) == "1"`). `_run(rooms, cache, 2)` and `3` stay: they set the width explicitly.
- `tests/imprint_solver_test.gd:43-50`: the 1.0 s and 0.5 s negative cases should still hold; if 1.0 s now crosses, say so and lower it to a duration that truly cannot, as a reported judgement.

### 7. New tests (mutation-check each, per project rule)

`tests/imprint_test.gd`, new `_shrink()`:

- Width 3, 1.5 s, new platform at `Rect2(100, 50, 30, 10)`: `rect` is the whole 30 px at age 0.25; after `update_footing()` at age 0.75, `rect.position.x == 110` and `size.x == 20`; at 1.25 the middle block only (`position.x == 110`, `size.x == 10`); `expired()` at 1.5. Step through ages in order, as the tool does.
- The removal order for widths 1, 2, 3, 4, 5: the last block is `width / 2` (assert the final `rect` of each).
- Width 1 never changes `rect` before expiry.
- `blocks_left()` at 0.25 / 0.75 / 1.25 for width 3 is `[3, 2, 1]`.
- Blink: for width 3, nothing blinks at ages 0.1 to 0.2 (a block is not near its time), `blinking_off()` is true somewhere in 0.25..0.5 on a 0.1 s phase and `next_cell() == 0`; collision `rect` is unchanged while it blinks. For the last block (age 1.3 to 1.5) `next_cell() == 1`.
- `warn_time()` is capped: `ImprintPlatform.new(Rect2(0, 0, 30, 10), 0.3).warn_time()` is 0.05 (half a 0.1 share).
- A platform made with `shrinking = false` keeps `rect == full_rect` for its whole life and `blinking_off()` is false.

`tests/imprint_play_test.gd`:

- The default platform is 30 px wide.
- When a block goes, `player.solids.size()` is unchanged but the player's solids include the smaller rect; a player standing only on the left block falls when it goes; one on the middle block stands until expiry.
- The cooldown still starts at the final break, not when a block goes (reuse the PR #31 cooldown block with a shrinking platform: `cooldown_left == 0.0` after the first block goes, > 0 after expiry).
- With `DevSession.mode = DevSession.Mode.DEV_TEST` and `classic_imprint = true`, a placed platform has `shrinks == false` and keeps its width; **reset both afterwards**. With `classic_imprint = true` but `mode == NORMAL`, it shrinks anyway.

`tests/dev_session_test.gd`: `set_classic_imprint` is refused outside a dev test; turning it on clears platforms and the cooldown; `classic_imprint_active()` is false in NORMAL even with the flag set; it survives `retry`; `end` resets it.

`tests/dev_ui_test.gd`: `panel._classic` exists; toggling it reaches `DevSession.classic_imprint`; the indicator text contains "classic imprint" (read `panel._indicator.text` after a `_process`); Escape/Apply do not change it; it is not a key of `panel._draft()`.

`tests/imprint_solver_test.gd`: a world where the only landing is on an **outer** block is not counted. Build it like `_barrier`: a wall whose top only the outer block of the platform reaches, and assert room 2 is unreachable at width 3 but reachable at width 1 (where the outer block is the last block). Mutant: make `_lands_on` accept any block of the platform -> this check must fail. Second mutant: drop the last-block-only re-simulation -> a check with an arc that brushes an outer block must fail, or say plainly that none exists and remove the second simulation.

Mutants to try (all must make at least one test fail):

- shrink from the left only (drop the alternation);
- `blocks_left` with `floori` instead of `ceili`;
- skip `sync_solids` when a block goes;
- `classic_imprint_active` ignoring the mode;
- drop the `classic_imprint = false` in `_replace(normal)`;
- solver legs using the full width;
- start the cooldown when a block goes;
- the preview cache key without the blocks standing (if no test can catch it, say so in the PR).

### 8. Docs (same PR; a change that makes a doc untrue updates it)

`docs/design/game-design.md` (line numbers from `main`):

- Status table (line ~18): add a row "Shrinking Imprint, default width 3 and the Classic dev switch | Built".
- Imprint -> Placing (line 424 bullet and 426): the cell under the cursor is the left end; starting width 3.
- The duration paragraph (line 435) is rewritten: the platform is its own clock; one block goes each equal share of the life (life / starting width), from the ends toward the middle, left first; the next block blinks for its last 0.25 s; each block that goes shatters; the last block shatters at the end; nothing fades. Say the dotted border means "you placed this".
- "What it is for" (line 451+): a wider platform buys landing time and room, and the last block is the one the puzzle can count on.
- Upgrades table (line 474): width "Starts at" **3 cells**, "Grows to" **5** (it said "3, then 5"; the 3 is now the start). List the question of whether a width-3 pickup still means anything under Not decided.
- Starting values (line 492): width 3.
- Look list (lines 498-502): replace the dashes bullet with the dotted border and the blinking next block; mention the dashes exist only in Classic.
- Dev playtesting (line ~296-312): add the Classic switch to the optional switches paragraph ("three optional switches"), saying it is a session switch, not saved, not in loadouts, and why.
- Implementation reference, "Imprint in play" (lines 610-619): placing creates `ImprintPlatform.new(rect, duration, not classic)`; ageing calls `update_footing()`; the clock bullet (line 616) becomes "The footing and the look" with `blocks_left` (`ceil(cells * (lifetime - age) / lifetime)`), the closed-form order, `WARN_TIME` and `warn_time()`, the drawing, and a short Classic paragraph for the old dash clock.
- Implementation reference, "The solver" `ImprintSearch` bullet (line 631): the last-block model, one-block legs, the second simulation.
- "What the solver and the preview do not model" (line 652): add the outer blocks, and that the reach preview treats the cursor platform as full width.
- Decision log: a new entry "Imprint shrinks one block per interval (PR #33)" with the why (the platform is the clock; the dashes no longer mean anything), width 3 so the middle is real, interval life / width, the last-block solver model and what it gives up, Classic kept as a dev comparison switch, old saves alone, the border look, the warning rule.
- Guardrails, "The Imprint rule": append "The footing the solver counts on is the last block, for the whole life. A feature that changes the shrink order, the interval or the starting width must keep that model true, or change the solver with it."
- Not decided: whether Classic is removed once the user has played both; whether per-block shards are too busy; whether the first width upgrade should still exist when the start is 3.

`README.md`: the Dev playtesting "Player" description (the Classic switch is on the Player tab, a session switch); test-table rows for `imprint_test`, `imprint_play_test`, `dev_session_test`, `dev_ui_test` (line ~110); the `src/imprint/` row at line 146 ("`ImprintPlatform` (one platform, its shrinking footing and its look)"); the test count in README and `AGENTS.md` stays 21 (no new test files).

`AGENTS.md`: extend the Imprint bullet under "Working on the repo" by one clause: it shrinks from the ends to its middle block, and the solver counts only that block.

`docs/testing-checklist.md`, a new "Imprint shrinking" section of **unplayed** items: rooms 5 and 6 with a 3-wide shrinking platform; the blink warning reads and is not annoying; the dotted border reads and differs from the dotted cursor; per-block shards are not too busy; landing on an outer block feels fair; Classic switches cleanly both ways in F2; widths 1, 2 and 5 in F2. Mark the existing "The clock at 1.5 s" item as Classic-only.

## Must not change

- **The no-replacing rule and the cooldown behaviour** from PR #31. Shrinking must not start the cooldown, refresh age, or let a click through while a platform stands.
- **`imprint_duration` and the total life.** Only the footing changes over time.
- **`Save.VERSION`, the save format, and old saves.** A stored width stays what it was.
- **The Classic code path** (`blinked_off`, `lines_left`, `line_rects`, `_line_xs`, `blink_time`): the dev switch uses it, and the current tests describe it.
- **`DevCatalog`, `Abilities.STATS`, `data/upgrades.json` entries.** The switch is not an ability.
- **Rooms.** Do not edit `data/rooms/*.txt` to make validation pass; report instead.

## Dead ends and cautions

- Using today's 0.375 s dash interval for blocks: wrong, see the discrepancy above.
- Counting any block as footing in the solver: unsafe, because an accepted route could rely on a block that has already gone. The user chose the conservative last-block model.
- Putting the Classic switch into the saved loadout or `Abilities`: rejected by the user; it must not appear in normal saves.
- Not verified yet (assumed): that Godot's `Shatter` at a 10 px block centre reads well; that `ImprintReach` and `hazard_test` need no change; that rooms 5 and 6 pass the last-block model at width 3. Run the validator before building more on it.

## Open questions for the user

None blocking. Two judgement calls to **report in the PR**, not ask: the `warn_time` cap at half a share, and the border being drawn around the remaining blocks while the end block blinks.

## Verify

```
godot --headless --path . --import
for t in imprint_test imprint_play_test imprint_solver_test hazard_test cache_test dev_session_test dev_ui_test save_test; do godot --headless --path . --script tests/$t.gd; done
tools/validate.sh --no-cache      # exits 0; compare each room's "needs" lines with main
tools/validate.sh                 # with the cache; must agree
tools/check.sh                    # the full gate; leaves build/web/
tools/serve.sh                    # then the user plays on :8060
```

| Check | What to look for |
| --- | --- |
| Validator | exit 0; `needs` lines identical to `main` (they were identical in PR #31); note the `lands` time before and after the second simulation |
| Room 5 pit both ways, room 6 wall (`?room=5`, `?room=6`, with Imprint from F2) | crossing works with the 3-wide platform shrinking 0.5 s per block |
| Blink | the next block blinks in its last 0.25 s; the footing under the player does not change while it blinks |
| Border | white block with a black dotted inner border, different from the white dotted cursor outline |
| `?dev=1&room=5`, F2, Player tab, Classic on | full-width platform with dashes again; off -> shrinking; toggling clears platforms |
| Normal play (no `dev`) | always shrinks; no switch exists |

After finishing: run `tools/check.sh`, serve `build/web` on :8060, and report what was and was not played (nothing here has been played by a person).

## Process

- Work on `imprint-shrink`; one PR; never push to `main`.
- Commit messages and PR bodies go through files (`git commit -F .git/COMMIT_MSG_DRAFT`, `gh pr create --body-file`), never heredocs. Refer to work by PR number.
- Do not playtest in a cloud agent. The PR lists the mutants tried and what was not played.

## Session log

- 2026-10-25 — Replaced the PR #31 handoff (built and merged) with the shrinking-Imprint spec. Decisions: ends-to-middle order, default width 3, interval life / width, next-block blink, dotted inner border, session-only Classic switch, last-block solver model, old saves left alone.
- 2026-10-25 — Built the spec (PR #33). Deviations and measurements are in the pull request: the Classic switch is on the Player tab as decided (the bypass and retry switches it was modelled on are on the Rooms tab), the solver's landing checks got about three times slower (a warm validate went from 11.8 s to 29.4 s in the cloud), and the preview cache key's new term is redundant while `sync_solids` resets the key.
- 2026-10-25 — The user changed the order after playing PR #33: it is set at the click from the player's centre (farthest block first, nearest last), ties go to the block behind the player, and the player gains a facing (last left/right input, right on spawn, respawn, warp and retry) shown as a 2 x 2 block cut into the top right or top left of the body, one row down (first a `>`/`<`, then a dot, changed at the user's request), and tokens are now 2 x 2 dots in a centred triangle instead of plus shapes. The solver's last block is the one nearest the jump's start, either block on a tie. Width stays 3. Built on PR #33.
