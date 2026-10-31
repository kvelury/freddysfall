# Handoff: second 3TM tokens and room 12

Branch: `claude/3tm-token-placement-wru9ob` (pushed). Read `AGENTS.md`, `data/rooms/AGENTS.md` and the design doc's Guardrails before touching anything.

## What the user asked for

1. The second 3TM is `r9_3tm` in room 9 (`upgrade=tongue_lash`). Its three tokens become:
   - `r8_token`: stays where it is in room 8.
   - `r9_token`: moves to save room **s3**, on the furthest-right platform (the middle one, row 9, cols 10–14).
   - `r10_token`: moves to room 10's **bottom-right corner**.
2. s2 gets a new door to a new, empty, one-screen room. The door is guarded by breakable blocks, so the player needs Tongue Lash (the last ability) to get through.

Decisions the user made when asked (don't reopen them):
- s2's right wall already leads to room 7 (s2 is at `(-1,5)`, left of room 7's bottom screen). So the new room goes **left** of s2, at `(-2,5)`.
- **Save rooms may now hold tokens and breakable walls.** They still can't have a pickup, health pip, 3TM, spikes or moving platform.
- The s3 token goes on the row 9 platform.

## Status: built, committed and pushed (commit `56cbadd`)

| File | Change |
| --- | --- |
| `data/rooms/9.txt` | Removed the `T = token id=r9_token` legend line and its `T` (row 2, col 24 is now `.`). |
| `data/rooms/s3.txt` | Legend `T = token id=r9_token`. `T` at row 8, col 12, standing on the row 9 platform. **The id stays `r9_token`**, so saves still count it. |
| `data/rooms/10.txt` | `T` moved from row 5, col 11 to row 34, col 30 (on the floor, bottom right). |
| `data/rooms/s2.txt` | Left wall rows 14–16 are now `X`. Legend `W = breakable id=s2_doorwall`, with `W` at col 3, rows 14–16. Solid `#` roof on row 13, cols 1–3, so nobody jumps over. Cols 1–2 stay clear for the 2-cell door push. |
| `data/rooms/12.txt` | New. `trap: allowed`, 32×18, empty, with right-wall door rows 14–16. `P` at row 16, col 26. |
| `data/world.json` | Added `{"id": "12", "grid_pos": [-2, 5]}`. |
| `src/world/room_parser.gd` `_check_save_things` | Counts as "others" only legend types outside `save`, `token`, `breakable`, `platform`. Moving platforms and spikes keep their own errors. Message text updated. |
| `tests/entity_test.gd` | A save room with a token now loads. New cases: a pickup or health pip in a save room is still an error. A breakable in a save room now loads (that fixture's machine was moved to row 16, because it used to float over air). |
| `docs/design/game-design.md` | Save-room rule, flow paragraph ("Fourteen rooms"), world sketch, the room 9/10/s2/s3 entries, a new room 12 entry, and a decision-log entry. |
| `data/rooms/AGENTS.md` | Save-room sentence. "not in a save room" removed from the breakable rule. |
| `docs/testing-checklist.md` | New section "Second 3TM tokens and room 12". |

Verified:
- `godot --headless --path . --script tests/entity_test.gd` gives `ENTITY pass`.
- `tools/validate.sh --no-cache` gives `validate pass: 14 rooms, 72 of 72 ledges reachable` (exit 0, about 10 minutes cold).
  - Room 12 and s2's ledge behind the wall need `r9_3tm`. `r9_token` (s3) and `r10_token` only need the first 3TM's chain.
  - The 46 warnings are all "one-way (trap: allowed)" ledges.
- A scripted in-game recording showed each thing working:
  - s3's token is taken.
  - Room 10's corner token is taken.
  - Three lashes break `s2_doorwall`.
  - The player walks into room 12.
  - Coming back, the wall has grown back, and three lashes from the doorway side clear it again.

## What's left for you

1. **Run `tools/check.sh` and get it to pass.** It runs the 28 tests, validation without cache and the web export. It hadn't finished when this was written.
   - If a test fails because it relied on `r9_token` being in room 9, `r10_token`'s old spot, s2 having one door, or the world having 13 rooms, update the expectation to match the new layout.
   - Never weaken or skip a check (see `AGENTS.md`).
   - Likely places to look: `tests/reach_test.gd`, `tests/shaft_test.gd`, `tests/machine_test.gd`, `tests/imprint_solver_test.gd`, `tests/dev_ui_test.gd`, `tests/map_test.gd`.
2. Optional: `tools/render.sh 9 10 s2 s3 12`, then read `build/renders/*.png` to check the layout by eye.
3. If the README's description of `entity_test.gd` (README "Tests" table) needs it, add "save rooms may hold tokens and breakable walls".
4. Commit any fixes to the same branch and push with `git push -u origin claude/3tm-token-placement-wru9ob`.
5. **Don't open a pull request unless the user asks.** If they do, mention that the save-room rule was relaxed (a guardrail change the user approved).
6. Don't playtest or record video unless the user asks (see `AGENTS.md`).

## Environment notes (cloud container)

- `godot` isn't on PATH. Download Godot 4.7.2 (matches CI) into a temp folder and put it on PATH:
  ```sh
  mkdir -p /tmp/godot-dl/bin && cd /tmp/godot-dl
  curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
  unzip -oq g.zip && mv -f Godot_v4.7.2-stable_linux.x86_64 bin/godot
  export PATH=/tmp/godot-dl/bin:$PATH   # needed again in every new shell
  ```
- Run `godot --headless --path . --import` once before single tests.
- Cold validation and renders take about 10 minutes each. Run them in the background, and never two at once. Don't `git stash` while one is running, because it reads the room files.
- Video, if the user asks for one: a SceneTree script instantiates `res://src/world/world.tscn` with `start_override`, sets `Save.enabled = false`, and drives `Player.scripted_x/jump` and `TongueLash.scripted` + `lash()` (as in `tests/tongue_lash_test.gd`). Run it with `xvfb-run -a godot --path . --rendering-driver opengl3 --write-movie out/f.png --fixed-fps 60 --script <script> -- --dev`, then `ffmpeg` the frames into an mp4. Keep the script and output out of the repo (put them in `build/` or `/tmp`).
