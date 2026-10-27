# Room files and the movement envelope

Loaded when you work under `data/rooms/`. The rest of the agent guide is in the root `AGENTS.md`.

## Room files

A room is `data/rooms/<id>.txt`, and is listed in `data/world.json` as `{"id": "<id>", "grid_pos": [x, y]}`. The id is a number, or `s` and a number for a save room (`s1`, `s2`, …). `grid_pos` is the screen cell of the room's top-left corner, so a room one screen to the right of `s1` is `[1, 0]`. The file name is always the id.

A screen is **32 columns by 18 rows**, one cell being 10 px. A room is a whole number of screens in each direction: 32 or 64 columns, 18 or 36 rows. Two rooms may not occupy the same screen cell.

| Glyph | Meaning |
| --- | --- |
| `#` | Solid. |
| `.` | Empty. |
| `X` | A door: an opening in the room's outer wall. |
| `P` | Where the player starts. Required in the start room. In any other room it is where `--room=<id>` puts the player. |
| `~` | A cell that refuses an Imprint. Open air otherwise, and not drawn. |
| `^` | Spikes. Not solid. Drawn pointing away from the solid beside them (a floor first), so a column of `^` against a wall reads as wall spikes. The player dies on touching one. With health they come back on the last safe floor, and with none at their save room. |
| `-` | A moving platform's track, side to side. Open air. See the legend below. |
| `\|` | A moving platform's track, up and down. Open air. |

Letters and digits that the legend below defines are also allowed. Any other character is an error. Every cell on the border of a room has to be `#` or `X`, and an `X` cannot sit on a corner.

**Doors.** Doors are crossed with momentum: a body keeps its speed and its place along the wall, and is pushed about 20 px (two cells) into the next room, so leave that much clear space behind a door. A door in a floor drops the player in. A door in a ceiling lifts them: aim the room below so a platform within a jump of it leads up to the hole, and leave the room above floor on one side of the hole to land on. Draw an `X` run in the outer wall, one cell thick. It pairs with the `X` run on the facing wall of the room that sits next to it, and the two have to overlap along the wall. A door that crosses a screen boundary is split into one door per screen. If nothing sits on the far side, the door is sealed to wall until a room is placed there. If a room sits there and the doors do not line up, that is an error.

**Things in a room (the legend).** A room that holds a pickup, a token, a 3TM or a save machine starts with a header, then a line of three dashes, then the grid as usual:

```
exits: pickups
legend:
  T = token id=r2_token
  M = machine id=r4_3tm upgrade=double_jump value=1
---
######...
```

`T` and `M` are any letter or digit the glyph table does not use. Draw one once in the grid, in open air or on a platform, and never in the outer wall. A legend glyph is one thing: two tokens need two glyphs and two ids. `id` is required, stable, and unique across the whole world, because the save remembers a pickup by it: never rename one, and never derive it from where it sits. `upgrade` is a key of `data/upgrades.json` (`double_jump` (value 1), `gun`, `gun_cooldown`, `gun_shot_speed`, `imprint`, `imprint_width`, `imprint_duration`, `imprint_max_active`, `imprint_cooldown`, `imprint_effect`), and `value` is a whole number, a number, or an effect name to match. `imprint` itself takes no `value`. A pickup, token or 3TM that no jump can touch is a validation error. A `token` takes only an `id`: the player carries up to three. A `health` (`H = health id=r7_health`) is a health pip, also only an `id`: taking it adds one to the player's health, and `exits: pickups` waits for it like a token. A `machine` (a 3TM) takes `upgrade` and `value` like a pickup and gives that upgrade when it has been fed three tokens, or takes `prize=health` instead (exactly one of the two; no room uses it now) and gives a health pip. It fills 3 x 3 cells of open air, and its glyph marks the middle of the bottom row, so on a floor the glyph goes in the cell just above the floor. A `save` is the save machine of a save room, with no settings besides `id` (`S = save id=s2_save`). It is a split sphere that takes the player in, saves, and pops them out on the other side, once each time the room is entered. Its glyph marks the middle of the bottom row. Its zone is 5 x 3 cells of open air (the 3 x 3 it fills and one cell each side), and the five cells under the zone have to be solid, because the player is popped out onto either side and comes back to the middle. A save room (an id of `s` and a number) has exactly one, holds nothing else but platforms (no pickup, token, 3TM or spikes), and no other room may have one. The exit rules are `open` (the default), `pickups` and `saved`. `exits: pickups` blocks every door in the room until every pickup and token in it has been taken, and it is an error in a room with nothing to take. `exits: saved` blocks every door until the room's save machine has been used, and it is an error in a room without one. A header line `trap: allowed` marks a room that is a dead end on purpose (a drop the player cannot climb out of yet): the validator reports its missing way home as a warning and not an error. Use it sparingly, and take it off when the way out is built. A `breakable` is a breakable wall (`B = breakable id=r7_pipwall`), with no settings: draw its glyph on every cell of one connected shape (cells that touch along a side), not in the outer wall and not in a moving platform's track or the row above it, and not in a save room. It is solid, so the player can stand on it, and it looks cracked. Only the gun (`upgrade=gun`, from room 9's 3TM) breaks it, in 3 hits, and it grows back each time the room is built, so it gates a place for one visit and is never saved. The solver shoots from a ledge, along a straight line to a wall, once the world has given the gun, so a place behind a wall needs the gun (`tools/validate.sh` says which pickups); a wall with no such line, or one only reachable while falling, is out of reach. See `data/rooms/7.txt`, where it closes in the health pip (with a solid roof, so nobody drops in). A `platform` is a moving platform (`L = platform id=r8_lift speed=60 pause=0.2`): `speed` is pixels a second and required, `pause` is seconds at each end, 0.2 if left out. It is the one kind drawn as more than one cell: draw its glyph as one unbroken row, as wide as the platform, where it starts, and draw its track on from one side of it to where it turns, `-` from one end of the row (side to side) or rows of `|` across its columns above or below it (up and down). Every `-` and `|` has to belong to a platform. The row above everywhere it goes has to be open air (`.`, `~` or `P`), nothing may stand in its way, it keeps a cell clear of every doorway, and a save room cannot have one. Its clock starts when the room is built, at the drawn end. A rider is carried; leaving it keeps only the player's own velocity (`inherit_platform_velocity` in `movement.tres`, off, adds the platform's). The user's key for things in a drawing becomes legend lines: ask what upgrade and value a drawn pickup or 3TM is if the drawing does not say, and whether the room holds its doors shut.

For worked examples, open `data/rooms/s1.txt` (a save room: the machine on the middle platform, `exits: saved`), `data/rooms/2.txt` (one screen, a door in each side wall, a token, `exits: pickups`), `data/rooms/3.txt` (a token on a staircase of platforms), `data/rooms/4.txt` (a 3TM), `data/rooms/7.txt` (one screen wide and four tall, with a moving platform over spikes, two doors in its right wall and a health pip), `data/rooms/9.txt` (a lift going up and down, and a 3TM on a pillar).

## Movement envelope

Design to what the player can do, then let `tools/validate.sh` decide.

- A full jump rises about 5 cells (51 px). A platform 4 cells above where the player stands is comfortable. 5 is not reliable.
- A running jump on flat ground crosses about 7 cells.
- A tap rises about 1.5 cells.
- With double jump (the first power-up, from room 4's 3TM), a second jump in the air at the top of the first rises about 10 cells in all (102 px). The solver tries one air press at fixed moments after a ground jump or a walk off a ledge, so it can be a little pessimistic. Rooms 5 and 6 were drawn for Imprint and are `trap: allowed`, because a double jump crosses room 5's pit only one way.
- With the gun, a standing shot flies straight along the row the player's centre is on, and a jump lets them shoot any row up to the jump's top. A shot has no range limit.
- The player is one cell wide and one cell tall.
- Touching a ceiling door, a player leaves at least 180 px/s upward. That rises about 2 cells, so a hole in the floor above should be narrow enough, or have floor close enough, for the player to steer onto.
