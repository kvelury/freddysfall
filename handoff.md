# Handoff: player sprites, animation table, per-frame inventory marks

_Updated 2026-10-29._
_Written as a build spec: implement exactly as written, and ask before deviating._

> **Scope: build the NEXT PR only.** If you were told "work on the next PR plan from handoff" (or anything like it), that means **Phase 1 — Next PR** below, items 1 to 6, and nothing else.
> - **Do not build Phase 2 — Later** (the PNG sprite sheet). It is written down so it is not lost, not as work for this PR. Do not start it, do not scaffold it, and do not add files, folders, loaders or JSON for it (no `assets/sprites/`), even if a Phase 1 step looks like it would be easier with it. Keep the ASCII rows as the only source of the pictures.
> - Phase 2 is built only when the user asks for it **by name** in their own words, for example "build Phase 2" or "do the PNG sprite sheet". "Next PR", "the plan" or "the handoff" do not count. If you are unsure which they mean, ask before writing code.
> - When Phase 1 is done, stop and report. Do not go on to Phase 2.

> **Status: not started.** This is the follow-up to the Freddy-the-frog pull request (branch `freddy-frog-sprite`). That PR shipped the frog and the first round of clean-up (below, under "Done"). Phase 1 here is the next PR. Phase 2 is **not to be built** until the user asks for it by name (see "Scope" above). The previous handoff (menus, pause, popups, title cards) was built and merged as PR #53.

## Goal

The user, after the frog shipped: "critique the entire implementation … anything we can improve or change to make it scalable and robust for adding more sprites/animation in the future". The user approved a review and asked for its "next" and "later" groups to be written here, to do later.

In plain terms, Phase 1 makes three changes:
- **A new animation is one table entry, not five edits.** Today the edits are an enum value, constants, a `match` branch, logic in the animator, and timing constants.
- **The inventory marks follow the body.** Each picture says where its marks go, so the short landing picture keeps its marks.
- **The pose belongs to the player, not to one sprite set.** A second costume or character becomes a data change.

Phase 1 also brings in one choice the user made about how Freddy looks: up to two tokens and no Imprint line while landing (see "Decisions").

## Branch

- The frog work is on `freddy-frog-sprite`, cut from `main` at `92b111a` (PR #55).
- When this was written, that branch had **no commits and no PR yet**. Everything in "Done" is uncommitted in the working tree, waiting for the user to approve a commit and PR.
- Cut Phase 1 from the latest `origin/main` after the frog PR merges: `git fetch origin && git switch -c player-animation-table origin/main`.
- If the frog PR has not merged when you start, stop and ask the user. Do not stack on an unmerged branch without being told to.

## Done (in the frog PR, for context — do not redo)

- `src/player/freddy_sprites.gd` (new): the pictures as ASCII rows (`#` lime body, `=` lime legs, `+` white eyes, `o` black, `.` nothing; `COLOURS: Dictionary[String, Color]` maps them; `BODY_PIXEL`/`MARK_PIXEL` name what marks are cut from and become), 10 wide, facing right, mirrored for left. Drawn as a `Drawn` of colour `Layer`s. It holds:
  - `enum Pose { STAND, WALK, JUMP, LAND }`
  - `BODY` (8 rows), with `STAND_LEGS`, `WALK_LEGS` (8 pairs of rows) and `JUMP_LEGS` stacked under it
  - `LAND` (7 rows, `LAND_TOP := 3`)
  - typed inner classes `Frame` (`top`, `rows`), `Drawn` (`layers`, `rects_in(colour)`) and `Layer` (`colour`, `rects`)
  - `walk_length()` (= `WALK_LEGS.size()`)
  - `frames()`
  - `problems()`: a row not 10 wide, a character not in `PIXELS`, or a picture leaving the box
  - `rects(pose, step, facing, cut)`, cached in `static var _drawn`
- `src/player/player_animator.gd` (new): picks the pose, with no node. `LAND_TIME` 0.125 s, `WALK_SPEED` 1 px/s, `STRIDE_PER_PICTURE` 6 px. `land()` and `advance(delta, grounded, speed_x)` set `pose` and `step`.
- `src/player/player_body.gd`: a `top_level` node. `show_at` moves it to `corner(center)` (snapped) and redraws only on a new pose or step. `_draw` cuts `InventoryMarks.pixels(...)` from the picture. In a debug build `_ready` pushes `FreddySprites.problems()` as errors.
- `src/player/player.gd`: owns `var animator := PlayerAnimator.new()`. It calls `animator.land()` on touchdown and `animator.advance(...)` in `_process`. The old squash and stretch is gone.
- `src/player/inventory_marks.gd`:
  - `SLOTS` (1,6), (1,4) on the rear and the third at (4,5), in the middle level with the gap (the user's choice, late in this PR: on (1,2) the third ran into the rear pupil)
  - the Imprint line on row 7, cols 4–8
  - `pixels(tokens, imprint, face := 1)` mirrors for `face < 0`
  - the old 2×2 facing block is gone
- Tests:
  - `tests/display_test.gd` `_body` and `_poses`: the pictures are valid, inside the box, mirrored and cached; the animator is driven directly; one pass goes through a real player on engine ticks (`await _poses()`).
  - `tests/token_test.gd` `_marks`: the exact stack and line, and every mark lands on white for stand, walk and jump.
  - Eight mutants were tried, and all were caught.
- `tests/pixel_grid.gd` / `tools/pixel_check.sh`: `--baseline` now records at the current 640×360 as one pixel per world pixel, so a deliberate look change can be re-baselined.
- Docs:
  - `docs/design/game-design.md`: "The player's picture", the inventory paragraph and diagram, "Effects and small parts", and the Decision log entries under **Freddy the frog**
  - `README.md`, `AGENTS.md` (pixel check row), `docs/testing-checklist.md` ("Freddy the frog")

Read `src/player/freddy_sprites.gd`, `player_animator.gd`, `player_body.gd` and `inventory_marks.gd` in full before starting. They are short.

## Phase 1 — Next PR: build this (one PR)

Do the items in this order. Item 1 changes the types the others use.

### 1. The pose belongs to the player (`PlayerAnimator.Pose`)

**Problem:** `enum Pose` lives in `FreddySprites` (`freddy_sprites.gd:15`), so `Player`, `PlayerBody` and `PlayerAnimator` all depend on one sprite set to name a player state.

**Change:**
- Move `enum Pose { STAND, WALK, JUMP, LAND }` to `src/player/player_animator.gd`, as `PlayerAnimator.Pose`.
- Delete it from `FreddySprites`.
- Replace every `FreddySprites.Pose` with `PlayerAnimator.Pose`. Today it appears in `player_animator.gd`, `player_body.gd`, `tests/display_test.gd` and `tests/token_test.gd`; `grep -rn "FreddySprites.Pose" src tests` lists them all.
- `FreddySprites` maps a `PlayerAnimator.Pose` to an animation (item 2). It never decides which pose to show.

### 2. One animation table; the animator reports time and distance, the sprite set picks the frame

**Problem:** these change together but live in five places:
- the frame count (`WALK_LEGS`)
- the rate (`PlayerAnimator.STRIDE_PER_PICTURE`)
- the per-pose frame lookup (the `match` in `FreddySprites.frame`, `freddy_sprites.gd:95`)
- the special top offset (`LAND_TOP`)
- the walk-step maths (in `PlayerAnimator.advance`)

**Change, `PlayerAnimator`** (it stops knowing how many pictures there are):

```gdscript
var pose := Pose.STAND
## Seconds and ground px since `pose` began. Both start from 0 on every change of pose.
var time_in_pose := 0.0
var distance_in_pose := 0.0

func advance(delta: float, grounded: bool, speed_x: float) -> void:
	var landing := _landing_left > 0.0
	_landing_left = maxf(0.0, _landing_left - delta)
	var next := Pose.STAND
	if not grounded:
		next = Pose.JUMP
	elif landing:
		next = Pose.LAND
	elif absf(speed_x) > WALK_SPEED:
		next = Pose.WALK
	if next != pose:
		pose = next
		time_in_pose = 0.0
		distance_in_pose = 0.0
	time_in_pose += delta
	if grounded:
		distance_in_pose += absf(speed_x) * delta
```

- Remove `step` and `STRIDE_PER_PICTURE` from `PlayerAnimator`.
- Keep `LAND_TIME` and `WALK_SPEED` there. They are how long a state lasts and when it starts, not how its pictures play.
- **Behaviour must not change.** Walking still restarts from the first picture after a stand, a jump or a landing (it does today, through `_stride = 0.0`). Check the order: the first walk frame after standing must have `distance_in_pose` = one frame's run (1.5 px at 90 px/s and 60 fps), so the picture is still index 0.

**Change, `FreddySprites`** (the table):

```gdscript
## How one pose's pictures play.
class Animation:
	var frames: Array[Frame] = []
	## px of ground run per picture (by_distance), or seconds per picture. 0: the first picture only.
	var every := 0.0
	var by_distance := false
	var loop := true

	## The picture index for this long in the pose.
	func index(time: float, distance: float) -> int:
		if every <= 0.0 or frames.size() == 1:
			return 0
		var i := int((distance if by_distance else time) / every)
		return posmod(i, frames.size()) if loop else mini(i, frames.size() - 1)
```

- `static func animation(pose: PlayerAnimator.Pose) -> Animation` builds the table once into a `static var _animations := {}` and returns the entry. The entries, from the existing constants:

| Pose | Frames | every | by_distance | loop |
| --- | --- | --- | --- | --- |
| STAND | 1: `BODY` + `STAND_LEGS`, top 0 | 0 | — | — |
| WALK | 8: `BODY` + each of `WALK_LEGS`, top 0 | 6.0 | true | true |
| JUMP | 1: `BODY` + `JUMP_LEGS`, top 0 | 0 | — | — |
| LAND | 1: `LAND`, top 3 | 0 | — | — |

- Delete `LAND_TOP`, the `match` in `frame()`, and `walk_length()`. `frame(pose, index)` becomes `animation(pose).frames[index]`.
- `frames()` becomes all frames of all animations.
- `problems()` loops over the table and also reports an animation with no frames, and a non-zero `every` on an animation with one frame (the second only as a warning-level line, still in the returned list).
- `PlayerBody.show_at(center, pose, index)`: `Player._process` computes `index` with `FreddySprites.animation(animator.pose).index(animator.time_in_pose, animator.distance_in_pose)` and passes it.
- **Done means** adding an animation (for example a future HURT) takes three things: an enum value in `PlayerAnimator.Pose`, one rule in `advance`, and one row in the table. Nothing else.

### 3. Each frame places its own marks; mirroring happens once; the box size is defined once

**Problem:**
- `InventoryMarks` slots are box coordinates that only work because every frame shares `BODY`, and `LAND` breaks that: its third mark falls off the picture.
- Mirroring is done twice: `InventoryMarks.pixels(face)` mirrors the marks and `FreddySprites._draw` mirrors the rows.
- The width 10 is defined twice: `InventoryMarks.SIZE` and the row strings.

**Change:**
- **Box size:** add `const SIZE := Grid.CELL` (10) to `FreddySprites`. Delete `InventoryMarks.SIZE`. `PlayerBody.corner` (`player_body.gd:65`) and `problems()` use `FreddySprites.SIZE`.
- **Mark slots per frame:** add to `FreddySprites.Frame`:

  ```gdscript
  ## Where the inventory is cut on this picture, facing right, in box pixels.
  ## `tokens`: the left pixel of each 2 x 1 token line, bottom first; fewer
  ## than three hides the rest. `line`: the Imprint line's pixels; empty hides it.
  var tokens: Array[Vector2i] = []
  var line: Array[Vector2i] = []
  ```

  - Every frame built from `BODY` gets the standing slots, exactly as `InventoryMarks.SLOTS` is today: `tokens = [(1,6), (1,4), (4,5)]` and `line = [(4,7), (5,7), (6,7), (7,7), (8,7)]`.
  - `LAND` gets `tokens = [(1,8), (1,6)]` and `line = []` (the user's choice: up to two tokens, no line, while landing).
- **`InventoryMarks` becomes the rule, not the coordinates.** Replace `SLOTS`, `WIDTH`, `LINE_ROW`, `LINE_FROM`, `LINE_TO` and `pixels(tokens, imprint, face)` with:

  ```gdscript
  const WIDTH := 2
  const MAX_TOKENS := 3

  ## The pixels cut from `frame` for `tokens` carried and Imprint found, facing right.
  static func pixels(frame: FreddySprites.Frame, tokens: int, imprint: bool) -> Array[Vector2i]:
  	var out: Array[Vector2i] = []
  	for i in mini(mini(tokens, MAX_TOKENS), frame.tokens.size()):
  		for dx in WIDTH:
  			out.append(frame.tokens[i] + Vector2i(dx, 0))
  	if imprint:
  		out.append_array(frame.line)
  	return out
  ```

  `MAX_TOKENS` is the pocket cap: write it as `const MAX_TOKENS := GameState.TOKEN_CAP` (`src/autoload/game_state.gd:11`, verified to be `3`). If a headless script cannot see the autoload's class at parse time, use the literal 3 with a comment naming `GameState.TOKEN_CAP`, and add an assertion in `token_test` that they are equal.
- **Mirroring in one place:** `FreddySprites.rects(pose, index, facing, tokens, imprint)`:
  - takes the frame
  - gets right-facing cuts from `InventoryMarks.pixels(frame, tokens, imprint)`
  - marks them `o` on the right-facing rows
  - **then** mirrors the finished rows if `facing < 0`

  The cache key becomes `"%d/%d/%d/%d/%s" % [pose, index, signi(facing), tokens, imprint]`. `PlayerBody._draw` passes `_state.tokens` and `_state.abilities.imprint_unlocked`, not a pixel list.
- **Done means:** no code outside `FreddySprites` mirrors anything, and `grep -rn "SIZE - 1 -\|9 - " src` finds no mirroring.

### 4. The marks' look (built by item 3's data)

- **Standing marks stay as this PR left them.** The earlier plan to move the stack to rows 7, 5, 3 and the Imprint line to a "mouth" on row 2 is **dropped**: the user fixed the eye clash differently in this PR, with two tokens stacked on the rear at (1,6), (1,4) and the third in the middle at (4,5), and the line on row 7, cols 4–8. Do not move them.
- **Landing** (`LAND`, top 3) gets `tokens = [(1,8), (1,6)]` and `line = []`: up to two tokens, no line, while landing (the user's choice). Facing right, 3 tokens + Imprint:

  ```
  .+++...+++   row 3
  .+o+...+o+   row 4
  ##########   row 5
  #oo#####..   row 6
  ##########   row 7
  #oo#######   row 8
  ===....===   row 9
  ```

- The bottom landing token on row 8 sits directly above the rear foot (row 9). The user saw that in a preview and chose it; do not "fix" it.

### 5. Tests (rewrite to the new shapes; keep every existing assertion's intent)

**`tests/token_test.gd` `_marks()` (line 115).** Replace the slot and line assertions with the new exact layout:
- The standing frame, every token count 0–4, Imprint off and on:
  - the slots are `(1,6),(1,4),(4,5)` × 2 wide, in that order
  - more than three draws three
  - the line is row 7, cols 4–8
  - nothing shares a pixel
- The landing frame: at most two token lines, and never the line.
- **Touching check, generalised:** on every frame of every animation, facing both ways, with 3 tokens and Imprint, no black pixel of one group (each token line, the Imprint line, each pupil) is 8-neighbour adjacent to a pixel of another group. This is what catches a mark running into an eye again. `token_test` already checks this for the standing frame ("no two marks touch", "no mark is up by the eyes"); generalise it. Build the groups from `Frame.tokens`, `Frame.line` and the `o` cells of the picture's rows.
- Every cut lands on a `#` of its frame. This replaces the "lands on the frog" check at line 172, and must now cover LAND too.

**`tests/display_test.gd`:**
- `_body`: the table is complete:
  - every `PlayerAnimator.Pose` has an animation
  - `problems()` is empty
  - every frame is inside `FreddySprites.SIZE`
  - mirroring is exact (the existing mirror check)
  - the cache returns one object for a repeat call (the existing check, using `index`)
- `_poses`:
  - drive `PlayerAnimator` directly, as today, asserting `time_in_pose` and `distance_in_pose` reset on every pose change
  - assert `animation(WALK).index(t, d)` gives 0 at 3 px, 1 at 9 px and 2 at 15 px (keep the existing off-boundary values; 6.0 px exactly is a float boundary)
  - the landing still lasts 8 frames at 60 fps
  - keep the real-player pass, which awaits `physics_frame`
- **Mutation-check** every new test. The project rule is that the PR lists the mutants tried. At least:
  - drop the `time_in_pose` reset
  - mirror before cutting, not after (the cut columns come out wrong facing left)
  - give LAND the standing slots
  - a pupil moved to touch a slot
  - `every` ignored (always index 0)
  - a missing table entry

### 6. Docs (same PR)

**`docs/design/game-design.md`:**
- The inventory paragraph (line 220): the landing showing two tokens and no line.
- Regenerate its ASCII diagram from the code, not by hand. A scratch script that prints `FreddySprites` rows with `InventoryMarks` cuts for "3 tokens", "Imprint+3" and "Imprint only" is how the current one was made.
- "The player's picture" (line 238): add the animation table and how to add an animation (the three steps from item 2).
- "Effects and small parts": the `InventoryMarks`, `FreddySprites`, `PlayerAnimator` sentence.
- **Decision log** under **Freddy the frog** (line 841):
  - add an entry for the table, per-frame marks and mirroring once, with the reasons from "Goal"

**`README.md`:** the `src/player/` row and the token_test row (add "landing shows two").

**`docs/testing-checklist.md` "Freddy the frog":**
- add "landing shows at most two tokens and no line"

**Pixel baseline:** this PR changes the look on purpose. Run `tools/pixel_check.sh --baseline` on the final commit, then `tools/pixel_check.sh`, and say so in the PR.

## Phase 2 — Later: do NOT build (the PNG sprite sheet)

> **Not part of the next PR.** Read it only for context. Build it only when the user asks for Phase 2 or the PNG sprite sheet by name (see "Scope" at the top).

**When:** only when the user asks for Phase 2 or the PNG sprite sheet by name, which is likely to be when they draw sprites in an editor (Aseprite or similar) and want to drop the image in instead of hand-copying ASCII. Until then the ASCII rows are the right format: they diff, they review, and they match `PixelShapes` and the room files. If unsure, ask the user before starting.

**Spec, for when it is asked for:**
- **The sheet:** `assets/sprites/freddy.png`, one row of 10×10 cells per animation, in the table's order (STAND, WALK, JUMP, LAND), frames left to right.
  - Colours: **the sheet is drawn in authoring colours, one per character, not in the game's colours**, because two characters can share a game colour (body `#` and legs `=` are both lime `#C6FB65`), so a game colour cannot be mapped back to a character. The JSON gives the authoring colour of each character (for example `"pixels": {"#": "#c6fb65", "=": "#5aa02c", "+": "#ffffff", "o": "#000000"}`); the loader maps each opaque pixel to its character, fully transparent to `.`, and anything else is a `problems()` error naming the cell and pixel. `FreddySprites.COLOURS` stays the one place the game's colours are set.
  - A frame shorter than 10 (LAND) is drawn bottom-aligned in its cell. Its `top` is the first non-transparent row.
- **The metadata:** `assets/sprites/freddy.json`:

  ```json
  {"cell": 10, "animations": {
    "stand": {"row": 0, "frames": 1},
    "walk": {"row": 1, "frames": 8, "every": 6.0, "by_distance": true, "loop": true},
    "jump": {"row": 2, "frames": 1},
    "land": {"row": 3, "frames": 1, "marks": {"tokens": [[1,8],[1,6]], "line": []}}
  },
  "marks": {"tokens": [[1,6],[1,4],[4,5]], "line": [[4,7],[5,7],[6,7],[7,7],[8,7]]}}
  ```

  The top-level `marks` is the default, and an animation's own `marks` overrides it.
- **The loader:** `FreddySprites` loads the PNG with `load("res://assets/sprites/freddy.png") as Texture2D` and calls `.get_image()`. Do not use `Image.load_from_file`, because a raw PNG is not in the web export: `export_presets.cfg` line 9 only adds `*.txt` as non-resource files. It turns each cell into the same `Frame` rows, so everything after loading (`rects`, cuts, mirroring, cache, tests) is unchanged.
  - Import settings: lossless, no mipmaps, filter off.
  - Load errors go through `problems()` and `PlayerBody`'s debug `push_error`, never a crash. That is the repo's rule: errors are collected and reported, not thrown.
- **The ASCII constants:** delete them in that PR. Keep one source.
- **Check:** `tools/check.sh` builds the web export. Confirm `res://assets/sprites/freddy.png` is in `build/web/index.pck` (the frog appears at http://localhost:8060 after `tools/serve.sh`).

## Must not change

- **The 10×10 collision box, `MovementSim`, `MovementConfig` and the solver.** The frog is only a picture, and `tests/parity_test.gd` and `tools/validate.sh` hold the movement to the solver. No sprite work touches `src/player/movement_sim.gd` or `movement.tres`.
- **Every picture stays inside the 10×10 box, bottom-aligned.** The user decided the jump must not draw above the box (Decision log, "The jump picture stays inside the box").
- **The look of the four poses.**
  - Phase 1 moves the marks only.
  - The `BODY`, legs and `LAND` rows stay pixel for pixel.
  - The walk stays 8 pictures at 6 px each, and the landing 0.125 s.
- **`Player.facing`.** Imprint's tie-break and the gun read it (`tests/gun_test.gd`, `tests/imprint_play_test.gd`). Only how it is drawn moves.
- **`PlayerBody.corner` snapping and `top_level`.** They keep the frog on whole world pixels between physics ticks (`tests/display_test.gd`, `tools/pixel_check.sh`).

## Decisions (do not undo these without asking)

- **Two tokens stacked on the rear, the third in the middle; the Imprint line stays on row 7.** The user chose this on 2026-10-29, replacing their 2026-10-28 choice (rows 7, 5, 3 and a mouth line on row 2), because with the third on row 2 it ran into the rear eye. Built in the frog PR; see the design doc's Decision log.
- **Landing shows up to two tokens and no Imprint line.** The user chose this over hiding all marks and over today's behaviour (a mark falls off the short picture). It only lasts 1/8 s.
- **ASCII rows stay the source until the user draws in an editor.** A PNG sheet was weighed and deferred (Phase 2), because ASCII diffs and reviews like the rest of the repo's art.
- **The animator owns how long a state lasts (`LAND_TIME`, `WALK_SPEED`); the sprite set owns how pictures play (`every`, `loop`).** Keep that split: it is what lets a second sprite set reuse the animator.

## Dead ends (from the frog PR)

- **An `_poses()` test with awaits, called without `await`.** It reported pass before its second half ran. A mutant (removing `animator.land()`) survived until this was found. Any test helper that awaits must be awaited.
- **Calling `player._physics_process` by hand on a player in the tree.** The engine ticks it too, so it double-steps. Drive a real player by awaiting `physics_frame`, or drive `PlayerAnimator` directly.
- **Asserting a walk step exactly at 6.0 px.** At 90 px/s and 1/60 s the sum lands on the float boundary. Assert at 3, 9 and 15 px.

## Open questions for the user

- None for Phase 1.
- For Phase 2: the go-ahead itself (blocks all of Phase 2).

## Verify

```bash
godot --headless --path . --import          # after adding or renaming any class_name
godot --headless --path . --script tests/display_test.gd   # DISPLAY pass
godot --headless --path . --script tests/token_test.gd     # TOKEN pass
tools/check.sh                              # the full gate, ~16 min: 27 tests, validate, web export
tools/pixel_check.sh --baseline && tools/pixel_check.sh    # look changed on purpose: re-baseline, then compare
tools/build_web.sh && tools/serve.sh        # http://localhost:8060; hard-refresh (Cmd+Shift+R), the page caches
```

| Check | What to look for |
|---|---|
| Standing, 3 tokens + Imprint | Exactly as before this PR: the design doc's diagram. No black touches a pupil. |
| Facing left | The same picture mirrored, marks included: stack in cols 7–8, the third in 4–5, the line in 1–5. |
| Landing with 3 tokens | Two lines on rows 6 and 8, no Imprint line, for about 1/8 s. |
| Walk | 8 pictures, a new one every 6 px, restarting from the first after a stop. Unchanged from the frog PR. |
| `grep -rn "FreddySprites.Pose\|InventoryMarks.SIZE\|walk_length\|STRIDE_PER_PICTURE" src tests` | No matches. |
| Adding a pose | Adding a HURT pose (try it, then revert) needs only the enum, one `advance` rule and one table row. |
| `tests/parity_test.gd` | Still 0.0000 px apart: movement untouched. |

## Session log
- 2026-10-27: Wrote the menus, pause, controls, popups and title cards spec. Decisions are from the user Q&A in this session.
- 2026-10-27: Built to this spec on `in-game-menus`; see the status note at the top for the deviations.
- 2026-10-28: Replaced with the player-sprite follow-up (Phase 1 next, Phase 2 later) from the frog PR's code review; the user chose the token rows 7/5/3, the mouth line and two tokens on landing.
- 2026-10-29: The user moved the third token to the middle of the body in the frog PR; item 4's stack move and mouth line are dropped.
- 2026-10-29: Added the scope note: "the next PR plan" means Phase 1 only; Phase 2 only when the user names it.
