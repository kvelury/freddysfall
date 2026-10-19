# Freddy's Fall: guide for agents

Godot 4.7, GDScript. A metroidvania whose rooms are ASCII files. What the game is: `docs/design/game-design.md`. The order work is done in: `docs/plans/foundation.md`. How to run and test: `README.md`.

## Commands

Run from the repo root.

| Command | What it does |
| --- | --- |
| `tools/validate.sh` | Loads every room and solves the world. A room is not done until this exits 0. |
| `tools/render.sh [ids]` | PNGs of rooms and the world map in `build/renders/`. Read them to see what you built. |
| `tools/snap.sh <id>` | A real in-game frame of a room in `build/snaps/`. Opens a window for a second, so run it on the user's machine. |
| `godot --headless --path . --script tests/<name>.gd` | `reach_test`, `physics_test`, `parity_test`, `door_test`, `shaft_test`, `hazard_test`, `start_test`, `entity_test`, `save_test`, `pickup_test`, `imprint_test`, `imprint_play_test`. Each prints a pass line and exits 0. |
| `godot --path . -- --room=<id>` | Play starting in a room. In the browser, `?room=<id>`. In a debug build, F4, the number, Enter. |
| `tools/build_web.sh` then `tools/serve.sh` | The browser build at http://localhost:8060. |

After adding a script with a `class_name`, run `godot --headless --path . --import` once. A headless script cannot see the new class until then. `validate.sh` and `render.sh` do this for you.

## Playtesting

Do not playtest Freddy's Fall inside the Cloud Agent environment, and do not record a playtest video, unless the user explicitly asks. A headless or brief launch to confirm the game runs is fine. Manual playtesting should be started on the user's computer, using a local agent when needed, so the user can play it themselves.

## Room files

A room is `data/rooms/<id>.txt`, and is listed in `data/world.json` as `{"id": "<id>", "grid_pos": [x, y]}`. The id is a number. `grid_pos` is the screen cell of the room's top-left corner, so a room one screen to the right of room 1 is `[1, 0]`. The file name is always the id.

A screen is **32 columns by 18 rows**, one cell being 10 px. A room is a whole number of screens in each direction: 32 or 64 columns, 18 or 36 rows. Two rooms may not occupy the same screen cell.

| Glyph | Meaning |
| --- | --- |
| `#` | Solid. |
| `.` | Empty. |
| `X` | A door: an opening in the room's outer wall. |
| `P` | Where the player starts. Required in the start room. In any other room it is where `--room=<id>` puts the player. |
| `~` | A cell that refuses an Imprint. Open air otherwise, and not drawn. |
| `^` | Spikes. Not solid. The player dies on touching one and comes back on the last safe floor. |

Letters and digits that the legend below defines are also allowed. Any other character is an error. Every cell on the border of a room has to be `#` or `X`, and an `X` cannot sit on a corner.

**Doors.** Doors are crossed with momentum: a body keeps its speed and its place along the wall, and is pushed about 20 px (two cells) into the next room, so leave that much clear space behind a door. A door in a floor drops the player in. A door in a ceiling lifts them: aim the room below so a platform within a jump of it leads up to the hole, and leave the room above floor on one side of the hole to land on. Draw an `X` run in the outer wall, one cell thick. It pairs with the `X` run on the facing wall of the room that sits next to it, and the two have to overlap along the wall. A door that crosses a screen boundary is split into one door per screen. If nothing sits on the far side, the door is sealed to wall until a room is placed there. If a room sits there and the doors do not line up, that is an error.

**Things in a room (the legend).** A room that holds a pickup starts with a header, then a line of three dashes, then the grid as usual:

```
legend:
  U = pickup id=r2_imprint upgrade=imprint
---
######...
```

`U` is any letter or digit the glyph table does not use. Draw it once in the grid, in open air or on a platform, and never in the outer wall. A legend glyph is one thing: two pickups need two glyphs and two ids. `id` is required, stable, and unique across the whole world, because the save remembers a pickup by it: never rename one, and never derive it from where it sits. `upgrade` is a key of `data/upgrades.json` (`imprint`, `imprint_width`, `imprint_duration`, `imprint_max_active`, `imprint_effect`), and `value` is a whole number, a number, or an effect name to match. `imprint` itself takes no `value`. A pickup that no jump can touch is a validation error. The user's key for pickups in a drawing becomes legend lines: ask what upgrade and value a drawn pickup is if the drawing does not say.

For worked examples, open `data/rooms/2.txt` (one screen, a door in each side wall) and `data/rooms/3.txt` (two screens wide, one door).

## Movement envelope

Design to what the player can do, then let `tools/validate.sh` decide.

- A full jump rises about 5 cells (51 px). A platform 4 cells above where the player stands is comfortable. 5 is not reliable.
- A running jump on flat ground crosses about 7 cells.
- A tap rises about 1.5 cells.
- The player is one cell wide and one cell tall.
- Touching a ceiling door, a player leaves at least 180 px/s upward. That rises about 2 cells, so a hole in the floor above should be narrow enough, or have floor close enough, for the player to steer onto.

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
