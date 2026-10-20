# Freddy's Fall — game design

This is the game as specified so far: what it is for, the rules that shape it, and the numbers those rules run on. It is the design record. Where a piece is already in the build, the section says so. The softer palettes are specified and not built.

Implementation steps for the palette pass live in `docs/plans/soft-duotone-palettes.md`. Decisions stay here.

| Area | State |
| --- | --- |
| Movement, grid, rooms, doors, spikes, camera, map, transitions | Built |
| Room legends, pickups, abilities, autosave | Built |
| Imprint: finding it, placing it, the preview, the lifetime | Built |
| Exit rules: a room's doors blocked until a condition is met | Built |
| Tokens, carried and shown on the player, and the 3TM | Built |
| Imprint upgrades beyond the numbers (longer, more at once, bounce) | Designed, not built |
| The solver using Imprint, and what each room needs | Built |
| Softer two-color palettes | Designed, not built |

## What it is

Freddy's Fall is a sidescrolling metroidvania adventure. The player moves through a network of rooms. An ability they do not have yet is what opens the next path.

The first ability is Imprint: the mouse cursor becomes a platform. Until that exists, the rooms are a movement toy with a map. After it exists, room layout is the lock and the platform is the key.

## Philosophy

**Movement is a specific feel, taken from one place.** The jump comes from the variable-jump, apex hang, fast fall, jump buffer, coyote time, rounded-ledge correction, and momentum described in section 4 of the Hollow Knight notes. That section is the whole of the borrowing. Combat, charms, art, map style, and anything else from that source are not part of this game.

**The picture stays small on purpose.** Geometry is solid pixel blocks. The player is a square the size of one cell. Effects are few and they mean something: dust when you land, a halo on an exit, a sparkle on a platform you can reach, a shatter when a platform breaks. The drawing is one bit, black and white, so a block, a gap, and the player read instantly at 320×180.

**Two colors, gentler in the dark.** Pure black and white is the authoring language and the default look. It is harsh for playing in a dark room. The softer version is still exactly two colors, remapped at the end of the frame. The world does not gain a third color.

**Everything shares one grid.** The player, authored platforms, exits, and Imprint sit on the same 10 px cells. A jump you can see is a jump the movement numbers can make. Rooms are tested against the same simulator the player runs.

**A room is a place. The screen is a window.** A room may be one screen, or several screens side by side or stacked. Inside a room the view moves continuously with the player. Crossing into another room is a distinct act: a door, a slide of the frame, a new place on the map.

**The map and the level are the same doors.** An exit is an opening in the room's outer wall. The map draws that opening. Doors are inferred from which openings face each other, so the map cannot claim a connection the level does not have.

**It has to run in a browser, on a modest machine.** Godot 4, GDScript, the Compatibility renderer, and a web export with threads off, so a static server is enough and Safari does not need special headers. Physics is a fixed 60 Hz. The display may be 60, 120, or 144 Hz. The jump does not change with the refresh rate.

## Frame and scale

| | |
| --- | --- |
| Cell | 10×10 px. The player is one cell, a 10×10 box. |
| Screen | 32×18 cells, 320×180 px. This is the viewport, not the room. |
| Window | Integer nearest-neighbor scale, aspect kept. Default window 1280×720, which is 4×. |
| Physics | 60 ticks per second. 2D physics interpolation on. At most 8 steps per frame. |
| Display | `max_fps` 0, vsync on. Movement math uses `delta`, so the tick rate can change later without rewriting the feel. |
| Filter | Nearest. Pixels stay pixels. |

The camera snaps to whole pixels. The player stays interpolated. A camera sitting between pixels shimmers when the 320×180 view is scaled up by a whole number.

## Controls

| Action | Keys |
| --- | --- |
| Move | A / D, or Left / Right |
| Jump | Space, W, or Up |
| Down | S or Down. Reserved. No action is assigned. |
| Imprint | Left mouse button, once the Imprint has been found. Mouse only. |
| Map | Hold Tab, or hold M. M exists because a browser may steal Tab for focus. |
| Palettes | P, once that is built. Cycles and remembers the choice. |
| Frame rate | F3. Shows FPS and frame time. A development readout, not a player feature. |
| Warp | F4, a room number, Enter. Debug builds only. A development tool, not a player feature. |

Letting go of jump early is a short hop. Holding it is the full leap. A running jump goes farther than a standing one, because air friction is low and the jump keeps the speed you had on the ground.

## Movement

The player is a plain `Node2D` with a 10×10 box and no physics-engine body. Each tick `MovementSim.step` reads the input, applies the rules below, rounds corners, and collides the box with the room's solid rectangles. The reach solver advances its simulated body with the same `step`, so a jump the solver finds is a jump the player makes. `tests/parity_test.gd` holds the two to 0.01 px. All of these live in one `MovementConfig` resource (`movement.tres`), shared by the player and by the jump simulator. They are the starting values, and they are tunable. They were not retuned when the first rooms were laid out. The rooms were laid out to the arc these numbers actually produce.

A full jump rises about 51 px (about 5 cells). A running jump on flat ground travels about 70 px (about 7 cells). A two-frame tap rises about 15 px.

| Rule | Value | What the player feels |
| --- | --- | --- |
| Jump speed | 267 px/s | The upward burst. |
| Gravity | 740 px/s² | The usual pull. |
| Variable jump | Release while rising multiplies vertical speed by 0.4 | Tap for a short hop, hold for the full leap. |
| Apex hang | Gravity ×0.5 while vertical speed is under 40 px/s | A moment of float at the top, enough to steer. |
| Fast fall | Gravity ×1.8 while falling, capped at 300 px/s | The drop is decisive. Landing is readable. |
| Run speed | 90 px/s | |
| Ground accel / friction | 900 / 1200 | Starts quickly, stops quickly. |
| Air accel / friction | 600 / 300 | You can steer, and you keep drifting after you let go. |
| Jump buffer | 0.12 s | A jump pressed just before landing still happens. |
| Coyote time | 0.10 s | A jump pressed just after walking off a ledge still happens. |
| Corner correction | 3 px | Feet clipping a ledge by 3 px or less get pushed up onto it. A head clipping a corner by 3 px or less while rising gets pushed sideways. Both use a movement test, not a teleport through the block. |

Feedback on the body is small. The square squashes and stretches by 1 px on jump and landing. Landing kicks 2–3 dust pixels at the feet. Those pixels are not interpolated, so they appear at the feet and not halfway across the screen.

Authored jumps are checked with the same simulator. If a test says a running jump from one ledge lands on the next, that is the jump the room is asking for. Jumping straight up into a 10 px platform from underneath bonks. The approach is from the side.

## Rooms

A room is an ASCII file, `data/rooms/<id>.txt`. Its id is a number (`1`, `2`, `3`, …), so the set can grow past twenty-six, and it is the only thing `data/world.json` needs to find the file. Its width and height are a whole number of screens. `grid_pos` in `data/world.json` is the screen cell of the room's top-left corner. The room occupies every screen cell in its rectangle. Two rooms may not occupy the same screen cell.

| Character | Meaning |
| --- | --- |
| `#` | Solid. Rows of `#` merge into rectangles, so cell edges do not snag the player. |
| `.` | Empty. |
| `X` | An exit opening. It has to sit on the room's outer edge, and not on a corner. An opening that crosses a screen boundary is split into one exit per screen. |
| `P` | Where the player starts, the first time, in the start room. Also a standable mark used when entering, and where the player is put when a room is started in directly. |
| `~` | A cell that refuses an Imprint. Open air otherwise, and not drawn. |
| `^` | Spikes. Not solid: the player can walk into them, and dies. |
| a letter or digit | A thing named in the room's legend. See below. Open air. |

Every glyph lives in one table, `src/world/tiles.gd`. A character that is not in it is a load error, not an empty cell. Every cell on a room's outer border has to be `#` or `X`, so the player cannot walk out of the world. Load collects every problem it finds (`WorldData.errors`) instead of stopping at the first. `tools/validate.sh` prints them and exits non-zero, and a debug build lists them on screen.

**Doors are the openings that face each other.** The destination of an exit is the room that occupies the neighboring screen cell. That exit pairs with the one opposite-edge opening whose span overlaps it. Load reports an error if a neighbor exists and the match count is anything other than one. An empty neighbor is allowed: an opening with nothing on the other side is sealed to solid wall at load, and opens up on its own once a room is placed there.

Each opening is a specific door. A room can have more than one. "A distinct entrance and exit" means each opening is that paired door, drawn on the map, and not a generic "any left edge leads to the room on the left."

Every opening that is left gets a halo: a dithered half-disc of light in the gap, with a pulse, so the way out reads before the player touches it. A sealed opening is plain wall and has none.

**Crossing.** Touching an exit pauses input and builds the next room at `grid_pos × 320×180`. Rooms share world coordinates, so the player does not change place: they keep their height along a side wall, or their column along a floor or ceiling, and are pushed just far enough into the next room to clear the far door's trigger (about 20 px past the wall). If the two doors are not level, the player is carried along the wall into the far door's span. If a wall is right behind the far door, the push is shortened. The camera slides to the view at that entry over about 0.5 s, ease in and out, and then the old room is freed and control returns with the velocity the player had at the door. Only the current room is in the scene, plus the next one during the slide, so a larger world does not cost more per frame.

An **up** door lifts a slow player: they leave it rising at 180 px/s at least, so touching a ceiling door near the top of a jump does not stall in the doorway. A **down** door drops them in with whatever speed they had.

**Blocked doors.** A room can hold its doors shut until a condition is met (see Exit rules below). While it does, each doorway is filled with a **block**: a solid frame around a checker of pixels, drawn where the halo would be. The block is solid and does not change rooms. There is no halo. When the condition is met the blocks shatter and the halos appear at once, and the player can leave.

**Dying.** Touching spikes, or leaving the room's outline by more than 60 px, shatters the player into a burst of pixels for about 0.6 s, and then puts them back on the last safe floor. A floor is safe if the player stood on it, it is the room's own floor, and it is not within a cell of spikes or within two cells of a doorway. An Imprint is never safe floor, because it breaks: standing on one over spikes and dying brings the player back on the real floor they stood on before, not in the air where the platform was. The safe floor can be in the room before: dying right after a door puts the player back through it. Spawning in a room also counts as a safe floor.

The last eight stretches of floor are remembered. If the player dies again before standing anywhere after a respawn, that respawn spot was no good and they go back one stretch, so a bad spot can cost one extra death and never a loop.

During the slide the camera is not following. It is on the tween. Afterward it follows again.

Solids are drawn in one chunk per screen, clipped to that screen, so a room several screens wide does not redraw geometry the camera cannot see. The player collides with every solid in the room, drawn or not, so it can land on a platform that is just off screen. Touching a door is a box overlap tested every tick.

### Exit rules

A room's header can carry a line `exits: <rule>`. The rule says when its doors work. It applies to every door in the room, the one the player came in by included. The rules are listed in `src/world/exit_rules.gd`:

| Rule | The doors work when |
| --- | --- |
| `open` | always. This is what a room with no `exits:` line has. |
| `pickups` | every pickup and token in the room has been taken. |

`exits: pickups` in a room with nothing to take is a load error, because it would never mean anything. The 3TM does not count as something to take. A rule is tested when the room is built and again each time the player takes something in it, so reloading a save in the middle of a room puts the blocks back or leaves them gone as the flags say. Adding a rule is a line in `RULES` and a case in `ExitRules.met`.

The header holds `exits:` and `legend:` in either order:

```
exits: pickups
legend:
  T = token id=r2_token
---
```

### Things in rooms

A room file may start with a **legend**: the line `legend:`, lines of `G = kind key=value ...`, and a line of `---`, before the grid. Each legend line gives a glyph one thing to stand for, and the glyph is drawn once in the grid.

```
legend:
  U = pickup id=r2_imprint upgrade=imprint
---
```

The glyph must be a letter or digit that `Tiles` does not use. Every legend problem is a load error with the room and the line: an unknown kind, a missing or misspelled setting, an upgrade or value that does not exist, a glyph drawn zero or two times, a glyph in the outer wall, a legend with no `---`. `id` is required on every thing. It is written in the file, never derived from position, so a room can be redrawn without losing what the save remembers. Ids are unique across the world.

The kinds are listed in `src/world/entities.gd`, with the settings each needs. There are three: `pickup`, `token` and `machine`. Adding a kind is a line there, a script in `src/world/entities/`, and a case in `Entities.create`. `Room.build` makes the things in a room and leaves out any that the player has already taken.

A **pickup** is a small diamond. Touching it gives its upgrade, shows one line at the top of the screen, and saves. It is gone from then on. What it gives is looked up in `data/upgrades.json`: each upgrade is a name, the ability it changes (`stat`), and a `kind`. A `max` upgrade raises a number and never lowers it, so finding a smaller one late does nothing. An `add` upgrade gains a named effect, once.

A **token** is a solid white diamond that bobs, where a pickup is hollow. Touching it puts it in the player's pocket. The player carries at most three. Touching a token with three already carried leaves it where it is and shows "You can carry 3 tokens", once for each time the player steps onto it, and it can be taken once there is room. A token that has been taken stays gone, even after it has been spent. A token has no settings besides its `id`.

A **3TM** (3 token machine, kind `machine`, settings `upgrade=` and `value=` like a pickup) is a square with a rectangle on top. The rectangle has three diamond-shaped openings. It fills 3 x 3 cells and the legend glyph marks the middle of its bottom row, so a 3TM standing on the floor has its glyph in the cell above the floor. Its 3 x 3 cells have to be open air, and it is not solid: the player walks in front of it.

- Touching it with no tokens shows how full it is ("3TM: 2 of 3 tokens").
- Touching it with tokens takes them all, one at a time. Each leaves the player's body, flies in an arc with a trail to the next empty opening, and fills it with a flash and a burst of pixels. The player cannot move meanwhile. An Imprint platform does not age meanwhile either.
- Filled openings stay filled, and the count is saved, so a player can bring one token now and two later.
- When the third opening fills, the machine shakes and flashes three times and a spark flies from its mouth to the player. The upgrade is then given, with the usual line of text at the top of the screen.
- After that the machine is **spent**: its outline turns dotted, and touching it does nothing. A second upgrade needs a second machine.

The player's body is the inventory. Each token carried cuts a small black diamond out of it, in a fixed triangle in the upper body: top, then left, then right. Once the player has Imprint, a line is cut across the bottom row. The tokens and the line never share a pixel, so more marks can go above the line later.

```
3 tokens       Imprint+3      Imprint only
##########     ##########     ##########
####.#####     ####.#####     ##########
###...####     ###...####     ##########
##.#.#.###     ##.#.#.###     ##########
#...#...##     #...#...##     ##########
##.###.###     ##.###.###     ##########
##########     ##########     ##########
##########     ##########     ##########
##########     #........#     #........#
##########     ##########     ##########
```

### Saving

The game saves to `user://save.json` when a room is entered and when a pickup is taken, and loads it on start. The file holds a version number, the room and the position in it, the visited rooms, the abilities, the number of tokens carried, how full each 3TM is, and the flags (one per pickup taken, `pickup:<id>`, and one per token taken, `token:<id>`). On entering a room the position is where the player arrived. After a pickup it is the last safe floor in that room, so loading never puts the player in the air above spikes.

A file that cannot be read, or that a newer version of the game wrote, is moved aside as `save.json.bad` and the game starts new, so it is never overwritten. A save for a room that no longer exists keeps the abilities and the map and starts in the start room. Headless runs and games started with `--room=` or `?room=` never read or write a save. F4 only warps inside a normal game, which keeps saving. `--new-game` ignores the save and the next autosave replaces it. A save from before tokens existed (version 1) is also set aside, because it comes from a world where Imprint was free and its flags mean something else now. To change the save's shape, raise `Save.VERSION` and add a step to `Save._migrate`; to give up on older files, raise `Save.OLDEST`.

### The current slice

Six rooms, as content, not as the limit of the format. The flow they make: take the token in room 2 to leave it, take two more in room 3, spend all three at the 3TM in room 4 to get Imprint, and use Imprint to cross room 5.

- **1**, one screen at `(0, 0)`. Three tiers of platforms, each a running jump apart, and an exit in the right wall. This is the movement test.
- **2**, one screen at `(1, 0)`. The landing from 1's door, steps down to the right, and a floor-level door in the right wall. It has `exits: pickups` and a token on the first platform, so it cannot be left until the token is taken.
- **3**, two screens wide at `(2, 0)`. Entered through that floor-level door. Platforms carry the route across the second screen. The same door is the way back. A hole in the floor of its second screen drops down to room 4. A token sits on the upper left platform and another on the lower right one. The room can be left without them.
- **4**, one screen at `(3, 1)`, under that hole. A zigzag of platforms climbs back to the hole. The 3TM stands at the bottom left. A floor-level door in the right wall leads to room 5.
- **5**, one screen at `(4, 1)`. A pit of spikes 12 cells wide is too wide to jump, so crossing it needs Imprint: a platform put over the spikes. A door in the right wall, past the pit, leads to room 6. It is the first room that is open or shut by an ability.
- **6**, one screen at `(5, 1)`. Empty, with a door in the left wall. It is where the next room will go.

### Starting in a room

For testing, the game can begin in any room: `--room=<id>` on the command line, `?room=<id>` on the web, or F4 in a debug build while playing. The player is put on that room's `P`, or just inside its first door if it has none. An unknown id is reported and the start room is used.

### Checking rooms

A room is not finished when it loads. `tools/validate.sh` also plays the whole world with the movement simulator, starting from the `P` in the start room, and fails if the world cannot be played.

A **ledge** is a run of cells with air above and floor below. From each ledge the solver tries walking off either end, and jumps from every cell with the input held left, none, or right, and the jump held for a tap, a hop, or the full leap. Each try is the same `MovementSim` the player runs. A try that lands on another ledge, or touches a door, is an edge in the graph. A try that touches a door records the body's position and velocity there. `Door.crossing`, the same function the game uses, says where that body appears on the far side, and the solver lets it fall or walk from there to see which ledge it lands on. A body that touches spikes is dead, so a path through them is not a path.

- **Error:** a room, or a door in a reachable room, that no path from the start reaches.
- **Error:** a door that every body going through it lands on nothing after, because the room beyond has a void or only spikes under it. The check is that some entry lands on a ledge. It does not promise that every entry does, so a shaft can still be hard to climb out of: play it.
- **Error:** a trap, meaning a ledge the player can reach but from which no path leads back to the start. Falling into a pit too deep to jump out of is one. The first version of room 3 was one.
- **Error:** a pickup, token or 3TM in a reachable room that no sampled path touches. A path that touches it and then dies on spikes still counts, because the pickup was taken. Only paths that start on a ledge are tried, so a pickup that can be taken only by falling through a door onto it is reported as out of reach.
- **Error:** a room whose exit rule is never met. Its doors never work, so everything past it is out of reach and its own floor is a trap.
- **Warning:** a ledge nobody reached. The solver tries a fixed set of inputs, so a ledge it misses might still be reachable by a path it did not think of. Look at the render and decide.

`tools/render.sh` draws each room and the world map to `build/renders/`. Red bars mark unreachable ledges, yellow bars mark traps, and orange marks a door that was sealed.

**Imprint in the solver.** The solver takes the player's `Abilities`. With Imprint unlocked, a ledge gets extra edges: a player standing there can put a platform down, jump onto it, and jump from it.
- It does not try every platform. From each ledge the usual jumps are simulated once, and a platform is a candidate only where one of those jumps comes down through the top of a cell row, and only if it is a legal place (the same `ImprintRules` the cursor uses) within a jump of something still out of reach. Each candidate is then checked by simulating the jump again with the platform in place. A platform that passes is searched from like a ledge of its own.
- A platform lives `imprint_duration` seconds, so each of the two jumps is cut to half of that less a little spare time. A one second platform crosses nothing.
- A ledge that cannot get home is searched the same way, with the ledges that can as the targets, so crossing a pit one way with a platform and having no way back is still a trap.
- Left out: putting the platform down in mid-air, and using two in a row. A room that needs either is reported as out of reach even if a player could do it. A room that needs the platform in a place the preview calls dotted is also not found.

**What a room needs.** `tools/validate.sh` solves with the starting abilities, takes every pickup that solve could reach, solves again with what they gave, and repeats until nothing new turns up. A room, a ledge, or a pickup that only opens in a later round lists the pickups it needs, cut down by dropping them one at a time to a set it still opens with. Example, from the current world: `Room 5: the ledge on row 16, cells 22-31 needs r2_token, r3_token_high, r3_token_low, r4_3tm`. Errors come from the last solve, so a room that stays shut even with every pickup is an error. Tokens and 3TMs are part of this. A token reached is taken. A 3TM reached gives its upgrade if three tokens are taken for it, and several machines are paid in the order of their ids. A room with an exit rule keeps its doors shut in the search until what the rule asks for has been reached, so a room is only open if the player can first do what it asks. The search does not model the carry limit of three (a player who cannot take a fourth token before spending three is not caught), and it does not treat a blocked doorway as a wall for a body falling through a chain of doors. A trap is judged where the player could first be in it, with the fewest abilities, because a player who has not found Imprint yet is also stuck in a place that needs it to leave.

## Camera

The camera shows one screen, and it stays inside the room.

- A room that is exactly one screen locks the camera to the room's center. It never scrolls.
- A wider or taller room follows the player, clamped so the 320×180 view never leaves the room, then rounded to whole pixels.
- The follow target is the player. During a door slide, follow is off until the slide finishes.

## Map

Hold Tab or M. The game pauses. A dim covers the playfield over about 0.1 s, and a panel scales from 0.92 to 1. Releasing the key dismisses it.

Visited rooms are outlined rectangles. The current room is filled. The player is a blinking pixel. Exit gaps break the outline where the doors are, and a connector joins a door to the door it leads to. The connector is drawn once the room on the other side has been visited.

A room that spans screens is one rectangle, not a row of separate rooms. The gap that normally separates neighboring rooms is filled in across the screens that room owns, so the shape on the map matches the continuous space. Door gaps and the player marker are placed per screen, so a door on the second screen sits on the outer edge of that wide rectangle, in line with a one-screen neighbor.

The room layer is drawn into a viewport and redrawn when the current room changes or a new room is visited. Each frame after that is the texture plus the marker. The view centers on the current room and clamps when the map is larger than the panel.

## Look, and the softer palettes

Built today: pure black background, solid white geometry and player. Glows and the map dim use ordered dithering or alpha. The map's current-room fill is an opaque gray, because a translucent white is premultiplied twice in the web build and disappears.

Designed, not built. Pure black and white stays the way art is drawn. One full-screen pass at the end of the frame remaps brightness onto a two-color palette: `mix(background, foreground, luma)`. No sprite is recolored by hand. The halo dither, the map dim, and any future sparkle or shatter pick up the palette because they are already shades of the same image.

| Palette | Background | Foreground | |
| --- | --- | --- | --- |
| Paper and Ink | `#1E1C1A` | `#DCD3C1` | Default |
| Amber Terminal | `#1B1612` | `#D9B27C` | |

Both are about 10–12:1 contrast, down from 21:1 for pure black on white. P cycles them. The choice is saved and restored, including in the browser. The page behind the canvas uses the same background, so the letterbox matches.

The build steps for that pass are in `docs/plans/soft-duotone-palettes.md`.

## Imprint

Status: the first version is built: finding it, placing it, the reach preview, the lifetime, and the rules below. The solver does not know about Imprint yet, so `tools/validate.sh` cannot prove that a room is open or locked by it. Widening, lengthening and the other upgrades are stored as numbers and unused.

Imprint is the ability that makes Freddy's Fall a metroidvania. The mouse cursor is a platform. The player places it, jumps from it, and uses longer, longer-lasting, and stranger versions of it to open paths that the authored rooms withhold.

### Fantasy

The cursor is a promise of a foothold. Before the click, the player can see whether that foothold is one they can actually reach. After the click, it is real for a few seconds, and then it breaks.

### The platform

The cursor snaps to a cell. That cell is the platform's left edge. The platform is `width_cells` wide and one cell tall. It is never rotated and never placed between cells. It shares edges, heights, and jump distances with the authored platforms, which are about four or five cells wide.

At the start, `width_cells` is 2: the player's width plus one spare cell. The first description of that spare was "one pixel." On this grid one cell is the player, so the spare is one cell.

### Placing

Left click places the platform under the cursor. There is no keyboard or gamepad way to place one, and none planned for now. The code gets the target cell from one function, so another input can feed it later.

- Only one imprint exists at a time. Placing another destroys the one that is already out, and the new one is placed at once, with no wait. A later upgrade may allow more than one.
- It has to lie fully inside the current room. The room is the whole room, including every screen it spans, not the visible viewport.
- It cannot overlap level geometry, spikes, or a door's trigger zone and the cell around it, so it cannot wall off a doorway or cover spikes.
- It cannot overlap the player.
- A `~` cell refuses it. That is how a puzzle can forbid the obvious ledge without changing the jump rules. `~` cells are not drawn: the player finds one by being refused there.

A platform may sit just above spikes. Bridging a spike pit with a platform a few cells over it, to jump from, is a core puzzle.

A placed platform is solid on every side, like authored floor. It can be stood on, bumped from below, and walked into. When it breaks under the player, they fall.

A legal placement lasts `duration` seconds, 4 at the start. For the last 1 second it blinks. Then it shatters into pixel shards. It does not fade out.

### Reach, before the click

The cursor has three looks, chosen before the player clicks.

- **Reachable.** The platform is drawn filled, with a small sparkle on it. Some jump the player can perform from their current position lands on its top.
- **Unreachable.** The platform is drawn as a dotted outline. No tested jump lands on it. The player can still place it.

The check includes being in the air. It starts from the player's real state: on the ground, or airborne with their current velocity. It tries a small set of jumps, not every possible input: hold left, hold nothing, or hold right, and release the jump at a few different times. Those paths use the same movement rules as the player, against the room's solid rectangles. If any path lands on the candidate platform's top, the cursor is filled.

The check runs again only when the player's cell, the cursor's cell, or whether the player is on the ground changes. Moving inside a cell does not recompute it.

- **Unavailable.** An illegal cell (outside the room, overlapping geometry, spikes, a door or the player, or marked `~`) is not a placement. No platform is drawn there, only a small ×, so it is never mistaken for a legal platform that merely cannot be jumped to. Clicking does nothing.

The operating system cursor is hidden while Imprint is available, because the preview is the cursor.

### What it is for

Imprint is the gate, the puzzle, and the traversal tool.

- A gap wider than a running jump is closed by a platform the player can reach and place.
- A route that needs a wider platform, a longer-lived one, or a platform that bounces stays closed until that upgrade is found.
- A `~` region is a place the designer has decided must be crossed some other way.
- Placing the one platform spends the previous one, so a puzzle can require the player to choose which gap to bridge.

Authored rooms should be solvable only with the upgrades available up to that point. The check the cursor uses is the same idea as the test that proves a room's own jumps: if the cursor says a platform is reachable, a player who jumps the way the check assumed can land on it.

### Finding it

The player does not start with Imprint. They earn it. A token lies in room 2, which cannot be left until it is taken, two more lie in room 3, and the 3TM in room 4 takes all three and gives Imprint. From then on the cursor is a platform, and a line appears across the player's body.

Tokens are the currency for upgrades, and a 3TM is the shop. Tokens are scattered through the world to be found by exploring, up to three at a time in the pocket, which puzzles are built around. Each 3TM is set to give one upgrade, so later upgrades (the ones below) mean placing more machines. How many tokens each costs is three for now.

### Upgrades

Upgrades are pickups in the world, written into a room's legend and drawn with their own character, and kept on the player once collected, and in the save. Leaving a room does not take them away.

| Upgrade | Starts at | Grows to |
| --- | --- | --- |
| Width | 2 cells | 3, then 5 |
| Duration | 4 seconds | longer |
| How many at once | 1 | stays 1 unless a later upgrade says otherwise |
| Behavior | a still platform | bounce, and others after that |

Width, duration, and behavior are the three things a room can demand. A later room can need five cells of width, or a platform that lasts long enough to cross two jumps, or a bounce, and the layout is what enforces it. There is no separate key item.

Bounce is the first special behavior. Others can be added the same way: a property of the placed platform, found as a pickup, and required by some later gap.

Ideas for later upgrades, none of them built:

- A longer platform.
- More than one platform at a time. Placing one then stops destroying the other, up to the count.
- A longer life for the platform.
- A bouncy platform.

The starting values are the defaults in `Abilities` (`src/core/abilities.gd`): width 2, duration 4 seconds, one at a time, no special behavior, and Imprint itself locked. They live in `GameState.abilities`, and the width and duration are read when a platform is placed.

### Look

Imprint uses the same black-and-white pixel language as the rest of the game.

- Filled cursor with a sparkle: you can get there.
- Dotted outline: you cannot get there from here.
- A small ×: you cannot put one here.
- Blink in the last second: it is about to break.
- Shatter into pixel shards: it is gone.

The sparkle and the shards are small. They should read at 320×180 and survive the softer palette, because that palette remaps the frame rather than the sprites.

## Not decided

- What S / Down does.
- How hard a bounce platform throws the player, and whether the player aims it.
- A gamepad or keyboard way to aim and place an Imprint.
- How many tokens an upgrade after Imprint should cost, and whether the pocket should ever hold more than three.
- What a spent 3TM should offer, if anything.
- Whether `~` cells should ever be drawn.
- Sound, throughout.
- A way to start over from inside the game. `--new-game` does it from the command line and the web address.
- Where the player resumes: a dedicated save point glyph, if autosave on room entry feels wrong.
