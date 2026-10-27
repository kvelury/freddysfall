# Handoff: render at 640×360 (2×) with the identical look

_Updated 2026-10-27. Written as a build spec: implement exactly as written, and ask before deviating._

> **Status: built, not yet played by a person.** Built to this spec on branch
> `claude/sharp-pascal-l7wh9r`. `tools/check.sh` and `tools/pixel_check.sh` pass; the
> judgement calls are listed in the pull request. The previous handoff (shrinking
> Imprint, PR #33) was built.

## Goal

The game renders at 320×180, and the window scales that by a whole number. The user wants more resolution to work with: sharper text now, and later more detail on the character, the backgrounds and the rooms. **Nothing may change functionally, and the world must look and move exactly as it does today: blocky, pixelated, two colours.** The only visible change in this pass is that text is sharper.

In the user's words: "Nothing should change functionally, gameplay needs to be identical to today, and everything should look and work the same way. Only the resolution is bumped up."

## Branch

Cut `resolution-2x` from the latest `origin/main` (`git fetch origin && git switch -c resolution-2x origin/main`). One pull request.

Uncommitted: nothing. This file arrives on `main` by its own small PR.

## Decisions the user made (do not re-litigate)

| Question | Decision |
| --- | --- |
| How much | **2×.** The viewport becomes 640×360. One game pixel (a "world pixel") is drawn as 2×2 screen pixels. The default window stays 1280×720, which is now 2×. |
| Units | **Keep game units.** A cell stays 10 world px. `Grid.CELL`, `Grid.SCREEN_SIZE` (320×180 world px), every movement number, the room files, the save, the solver and every gameplay test stay as they are. The camera zooms 2×. |
| Motion | **Snap to the old grid.** Everything in the world is drawn on whole world pixels, reproducing exactly what the 320×180 raster drew. Finer motion can be allowed later, one thing at a time, by the user's decision. |
| Text | **Same font** (Godot's default), same size on screen, same layout, rasterized at 2× so it is crisp. Antialiased edges are fine. |
| Window fit | **Accept Godot's built-in whole-number scaling.** A window that showed 320×180 at an odd multiple now drops a step. A maximized browser on a 1080p screen showed 1600×900 (5×) and now shows 1280×720, with wider black borders. Fullscreen 1080p (1920×1080), 720p, 1440p and 4K are unchanged. No custom scaler. |
| Map open/close | The 0.1 s grow from 92% to 100% may be drawn finer than today. That is allowed, and it is the one accepted difference in the world or UI shapes. |

## The rule this adds (a new guardrail)

**The world-pixel grid.** Every world-space drawing lands on whole world pixels. Node positions and rect corners are whole world px. Non-rectangular shapes are pixel pictures, not polygons. A finer drawing is allowed only for art that is meant to be finer, by the user's decision. Such art joins the `Display.FINE_GROUP` node group so the pixel check skips it. UI (CanvasLayers) is exempt, because its text is meant to be finer.

Add this rule to the design doc's Guardrails and to README's rules. `tools/pixel_check.sh` enforces it.

## What changes, file by file

### 1. `Display` constants and snapping (new `src/core/display.gd`)

`class_name Display`, pure static, like `Grid`.

- `RENDER_SCALE := 2`.
- `VIEWPORT := Vector2i(640, 360)`, which must equal `Grid.SCREEN_SIZE * RENDER_SCALE`.
- `FINE_GROUP := "fine_pixels"`.
- `snapf(x) = ceilf(x - 0.5)`, plus `snap(v: Vector2)` and `snap_rect(r: Rect2)`, which snaps both corners.

`snapf` is the GPU's pixel-centre rule: a pixel is filled when its centre is inside, and left and top edges are inclusive. So snapping reproduces what 320×180 drew, including half-pixel cases (`x.5` goes to `x`). If the baseline diff (step 6) shows only one-pixel shifts at exact `.5` positions, switch to `floorf(x + 0.5)` and record that in the decision log.

`PixelArt` (in the same file, or in `src/core/pixel_art.gd`) turns a small ASCII picture into rects and draws them with `draw_rect`. `#` is on and `.` is off, the room-file idiom. It merges runs within each row.

Run `godot --headless --path . --import` after adding the new `class_name`s.

### 2. Project and camera

- **`project.godot`:** set `viewport_width=640` and `viewport_height=360`. Keep the window override at 1280×720, stretch `viewport`, aspect `keep`, scale `integer` and the nearest filter.
- **`src/world/world.gd` `_ready`:** set `camera.zoom = Vector2.ONE * Display.RENDER_SCALE`. Code is the source of the zoom. Leave `world.tscn`'s camera position at 160,90, which is in world px.
- **`Grid.camera_focus`:** unchanged. It still clamps with the world-px `SCREEN_SIZE` and still rounds with `.round()`.
- **The door slide** (`world.gd:448`) tweens `camera.position` to fractional values. Change it to `tween_method`, setting `camera.position = p.round()` at each step. Today the 320×180 raster rounded the fractional camera, so this reproduces it.
- **`Grid.SCREEN_SIZE`'s doc comment:** say that it is in world px, and that the visible area is the same 320×180 world px.

### 3. UI layers: same layout, sharper text

The UI scripts stay in 320×180 logical units. Try these options in order. Take the first one that passes the sharpness check (step 6: inside a text label's box, some 2×2 block is not one colour) **and** looks the same weight as today. Report which one you took in the PR.

1. **Layer scale.** Give each UI `CanvasLayer` `scale = Vector2.ONE * Display.RENDER_SCALE`, relying on Godot 4.7's font oversampling. The layers are Toast (`src/ui/toast.gd`), DebugOverlay (`src/ui/debug_overlay.gd`), DevPanel (`src/ui/dev_panel.gd`) and MapOverlay (`src/ui/map_overlay.gd`).
2. **Layer scale plus MSDF.** Do option 1 and also set `gui/theme/default_font_multichannel_signed_distance_field=true` in `project.godot`. MSDF text stays sharp under any scale, and the setting also covers `ThemeDB.fallback_font`.
3. **Fallback: multiply every size.** Give the layers no scale. Multiply every UI size, position, margin, border, minimum size and font size by `Display.RENDER_SCALE`:
   - The dev panel theme's `default_font_size` becomes 16.
   - StyleBox borders become 2.
   - The 12×6 CheckButton icons are resized ×2 with nearest filtering.
   - `tests/dev_ui_test.gd:189`'s 312×160 bound is doubled.

Anything that is not text stays chunky: a 1 px StyleBox border becomes 2 screen px, and each icon pixel becomes 2×2. Ask before deviating.

**The map** (`src/ui/map_overlay.gd`): make the room-id labels sharp too.

- Set the SubViewport's `size = VIEW_SIZE * RENDER_SCALE` (480×264).
- Put `MapLayer` under a new Node2D with `scale = RENDER_SCALE`. Then these stay as they are: the `MapView` maths, `VIEW_SIZE` (240×132 map units), `_layer.position`, and the `canvas_transform` that `map_test` reads.
- The TextureRect keeps the logical size `VIEW_SIZE`. Under option 1 or 2 that is one texel per screen pixel; under option 3, double its size.
- Lines stay 1 map px, which is 2 screen px.
- The Marker and the Legend are Controls in the panel, so they follow the layer.
- Leave the 0.92 to 1 panel scale alone (accepted).

### 4. Snap every world drawing that can sit between world pixels

These are the known sites. `pixel_check` finds any that were missed.

- **Player** (`src/player/player.gd`, `player.tscn`, `src/player/inventory_marks.gd`):
  - The `Player` node stays physics-interpolated, because gameplay, the camera and `shaft_test` rely on it.
  - The drawn body becomes a `top_level` node with interpolation off. Each `_process` places it at `Display.snap(render_position(Engine.get_physics_interpolation_fraction()))`.
  - Squash no longer uses `Visual.scale`. Draw the body as `snap_rect` of the scaled 10×10 box. Draw each inventory mark as `snap_rect` of its scaled 1×1 pixel. Compute both from the exact, unsnapped interpolated position, then make them local. This reproduces today's raster exactly, including a mark that briefly goes 0 or 2 px wide in the middle of a squash.
  - Keep `InventoryMarks.pixels()` unchanged, because `token_test` uses it.
- **Dust** (the `Dust` class in `player.gd`): keep the exact float position in a field, and set `position = Display.snap(exact)` in `_process`. The old `Rect2(-0.5, -0.5, 1, 1)` at p filled the pixel at `snap(p - 0.5)`. Draw it with `snap_rect` and confirm against the baseline.
- **Shatter** (`src/world/shatter.gd`): in `_ready`, set `global_position = Display.snap(global_position)`. Player deaths spawn it at float positions (`world.gd:322`, `world.gd:393`). The shard offsets are already rounded.
- **Moving platform** (`src/world/entities/moving_platform.gd`, `room.gd:75-99`):
  - First confirm that no gameplay reads the node's position. Collision goes through `Movers` and `PlatformPath`.
  - Turn interpolation off.
  - Keep the previous and the current tick's positions. In `_process`, set `position = Display.snap(prev.lerp(curr, fraction))`.
- **FlyingToken** (`src/world/flying_token.gd`): snap the first `global_position` (`:30`). Draw the trail dots and the spark with `snap_rect`.
- **Save-machine hop** (`world.gd:286-291`, and the `+0.5` centre at `save_machine.gd:100`): the player's snapped body handles it. Check it in `pixel_check` in the middle of a hop.
- **Classic Imprint dashes** (`src/imprint/imprint_platform.gd:170,173`, y + 4.5): draw them with `snap_rect`.
- **Shots** (`src/gun/gun.gd:83-86`): already rounded. Leave them.

### 5. Non-rectangular shapes become pixel pictures copied from today's frame

At 640×360, polygons and polylines would rasterize with finer stair steps. Replace each of these with a `PixelArt` ASCII picture, drawn at the same whole-pixel anchor. Bake the pictures from the 1× render **before anything changes** (step 6 `--shapes`).

- Spikes, in all four facings, two teeth per cell (`src/world/room.gd:333-346`, `_turn`).
- The token diamond (`src/world/entities/token.gd:49`).
- The pickup diamond and its 2×2 hole (`pickup.gd:44-46`).
- The FlyingToken's 12 px diamond (`flying_token.gd:62`).
- The TokenMachine's diamond outline (`token_machine.gd:112`, `draw_polyline` with width 1).

Keep the old polygon maths only where something else uses it. For example, hazard rects use cells, not the polygon.

### 6. The pixel check (new `tools/pixel_check.sh` and `tests/pixel_grid.gd`)

The check runs with a renderer, so it is not part of `check.sh`: a headless run has no renderer.

How the script runs:

- The shell runs `godot --path . --fixed-fps 60 --script tests/pixel_grid.gd -- <mode>`, under `xvfb-run -a` when there is no `$DISPLAY`.
- The script sets `Save.enabled = false`, so it never touches the real save.
- It seeds `seed(1)`, so dust and shards repeat from run to run.
- It sets abilities through `GameState`/`DevSession` the way the dev tests do, never through room files or the save.
- For comparisons it hides `ExitHalo` nodes (their frame follows the wall clock) and `Display.FINE_GROUP` nodes.

The modes:

- **`--shapes`:** draws each shape from step 5 with the current code at 1× and prints its ASCII picture.
- **`--baseline`:** for every room, captures frames of these scenarios into `build/pixel-baseline/`:
  - idle at spawn
  - a jump, with squash and stretch frames
  - landing dust
  - a death shatter
  - room 7's moving platform at several phases
  - a door slide part way through
  - the Imprint preview, a placed platform part way through shrinking, and the Classic switch
  - a shot in flight
  - a save-machine hop (s1)
  - a 3TM feed with a flying token
- **`--compare`** (the default) captures the same scenarios at 640×360 into `build/pixel-check/` and checks them:
  - With the UI layers hidden, **every 2×2 block is one colour** (the grid rule).
  - With the UI layers hidden, the frame downsampled 2× (the top-left pixel of each block) **equals the baseline**.
  - With the UI shown, it saves PNGs of the toast ("Game saved"), F3, the F2 panel on each tab, and the map at each zoom with dev labels. Each text box must contain 2×2 blocks that are not one colour, which shows the text is sharper.
  - It warps the mouse to a known screen pixel and checks that the Imprint preview lands on the right cell, which tests the camera zoom in the mouse mapping.
  - It prints `PIXEL pass`, or each failure with its room, scenario and coordinates.

A scripted capture is a brief launch, not a playtest, so AGENTS.md allows it. If Godot cannot render in the cloud container (no Godot install, or no working GL under Xvfb), say so, and give the user the exact commands to run it on their own machine.

### 7. Order of work

1. Commit the pixel check and `--shapes` with **no rendering changes**. Run `--shapes` and `--baseline` on that commit, which is main's look. Keep the baseline in `build/`; do not commit it.
2. Add `Display` and `PixelArt`, the project viewport, the camera zoom and the rounded slide, the chosen UI option, and the 2× map.
3. Add the snapping (step 4) and the pixel pictures (step 5).
4. Update the tests and docs (below). Run `tools/check.sh` and `tools/pixel_check.sh`; both must pass. Read the UI PNGs and a few world frames, and attach the key ones to the PR.

### 8. Tests

- **New headless `tests/display_test.gd`.** Add it to `check.sh`'s list. The count goes from 23 to 24 in `AGENTS.md` and README's test table. Also fix `check.sh`'s stale final message, which says "21 tests". The test checks:
  - `project.godot`'s viewport equals `Grid.SCREEN_SIZE * RENDER_SCALE`, with stretch `viewport`, integer scale and the nearest filter.
  - The world camera's zoom is `RENDER_SCALE`.
  - A table of `snapf` and `snap_rect` results, including `.5` and negative values.
  - `PixelArt` parsing, and each baked picture's size and pixel count.
  - The player's drawn body and marks are whole-pixel over a sweep of fractional positions and squash values.
  - The dust, shatter and moving-platform visuals are whole-pixel across fractions.
  - The UI layer scale (option 1 or 2).
- **`tests/shaft_test.gd:99`:** its bound is in viewport px, so it becomes `0.5001 * Display.RENDER_SCALE` ("within half a world pixel"). Update the message to match.
- **Everything else** must pass unchanged: parity, physics, the solver, saves, the map maths, token pixels and Imprint. If a gameplay test needs a change, gameplay changed: stop and ask.

### 9. Docs (in the same PR)

- **`docs/design/game-design.md`:**
  - The Frame and scale table. Cell: 10×10 world px. Screen: 32×18 cells, which is 320×180 world px, drawn at 640×360, 2 screen px per world px. Window: 1280×720, which is 2×. Text is drawn at 2×.
  - The Philosophy line about the picture (line 43).
  - The camera (lines 66, 387 and 712–714): it rounds to whole world px, and the slide is rounded too.
  - The map (line 748): the SubViewport is 480×264; map units are unchanged.
  - The shards line (531).
  - A **Decision log** entry with the decisions table above.
  - The new world-pixel-grid **Guardrail**.
  - The status table row.
- **`README.md`:** the `project.godot` line (140); rules 5 and 6 (whole world pixels, snapped visuals, `Display`); a code-map entry for `Display` and `PixelArt`; `tools/pixel_check.sh`.
- **`AGENTS.md`:** add `tools/pixel_check.sh` to the commands table, and update the test count.
- **`docs/testing-checklist.md`:**
  - Run `tools/pixel_check.sh`.
  - Check that text is sharp and the world looks unchanged at 1280×720 and fullscreen.
  - Note the accepted window-fit change.
- **`docs/plans/soft-duotone-palettes.md:21`:** the cost is one 640×360 quad, and the shader works per screen pixel at any resolution.
- **`tools/concept/`:** update `concept_hud.gd:31`'s card and `compose.py`'s docstring for 640×360 frames (2× to 1280×720).
- **`tools/snap.sh`:** no code change, but its frames are now 640×360.

## Ask before

- Any change to a gameplay number, a test expectation or the solver.
- Any visible world difference in the baseline diff that the `.5` tie rule does not explain.
- Choosing UI option 3, or any UI element that would look different in any way other than sharper text.

## Verification

- `tools/check.sh` passes: every headless test including `display_test`, the validator without cache, the web build and its integrity check.
- `tools/pixel_check.sh` prints `PIXEL pass`: no grid violations, no difference from the 1× baseline in any scenario, text measurably sharper, and the mouse lands on the right cell.
- Read the saved UI PNGs (the toast, F3, each F2 tab, each map level) and a few world frames.
- Run `tools/build_web.sh` and then `tools/serve.sh`. The user plays on their own machine and confirms that it looks and plays the same, with sharper text. Do not do this in the cloud.

## Later: drawing finer detail

Once this is in, a node can draw at half a world pixel (0.5 world px is one screen pixel). Such art goes in `Display.FINE_GROUP` and needs the user's decision. Everything else stays on the world-pixel grid.
