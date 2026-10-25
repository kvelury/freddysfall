# Freddy's Fall — game design

This is the game as specified so far: what it is for, the rules that shape it, and the numbers those rules run on. It is the design record. Where a piece is already in the build, the section says so. The softer palettes are specified and not built.

Two sections at the end are for whoever changes the code: **Implementation reference** says how each system is built and which constants matter, and **Decision log** says what was decided, what was tried and dropped, and why. `README.md` has the code map and the rules the code keeps. If a change makes any of these untrue, it updates them in the same pull request.

Implementation steps for the palette pass live in `docs/plans/soft-duotone-palettes.md`. Decisions stay here.

| Area | State |
| --- | --- |
| Movement, grid, rooms, doors, spikes, camera, map, transitions | Built |
| Room legends, pickups, abilities, autosave | Built |
| Imprint: finding it, placing it, the preview, the lifetime | Built |
| Exit rules: a room's doors blocked until a condition is met | Built |
| Tokens, carried and shown on the player, and the 3TM | Built |
| Save rooms, the save machine, `exits: saved`, and the health count that death uses | Built |
| Health pips: the pickup, how they show, refilling | Designed, not built |
| Imprint width, duration and multiple active platforms | Built; available in dev tools, not awarded by current rooms |
| Imprint bounce and other special behaviors | Designed, not built |
| Isolated dev tools, named loadouts, retries and door bypass | Built |
| The solver using Imprint, and what each room needs | Built |
| The solver's cache between runs (a repeat validate takes about 8 s) | Built |
| The map's three zoom levels, its legend, saved with the game | Built |
| Moving platforms: drawn with their track, ridden, and checked by the solver | Built |
| Softer two-color palettes | Designed, not built |

## What it is

Freddy's Fall is a sidescrolling metroidvania adventure. The player moves through a network of rooms. An ability they do not have yet is what opens the next path.

The first ability is Imprint: the mouse cursor becomes a platform. Until that exists, the rooms are a movement toy with a map. After it exists, room layout is the lock and the platform is the key.

## Philosophy

**Movement is a specific feel, taken from one place.** The jump comes from the variable-jump, apex hang, fast fall, jump buffer, coyote time, rounded-ledge correction, and momentum described in section 4 of the Hollow Knight notes. That section is the whole of the borrowing. Combat, charms, art, map style, and anything else from that source are not part of this game.

**The picture stays small on purpose.** Geometry is solid pixel blocks. The player is a square the size of one cell. Effects are few and they mean something: dust when you land, a halo on an exit, a shatter when a platform breaks. The drawing is one bit, black and white, so a block, a gap, and the player read instantly at 320×180.

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
| Map | Hold Tab, or hold M. M exists because a browser may steal Tab for focus. While it is held, Up or W zooms in and Down or S zooms out. |
| Palettes | P, once that is built. Cycles and remembers the choice. |
| Frame rate | F3. Shows FPS and frame time. A development readout, not a player feature. |
| Dev tools | F2 or DEV button. Editor/debug builds, or exports opted in with `?dev=1` / `--dev`. |
| Room picker | F4, a room ID (including `s1`), Enter. Starts an isolated test. |

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

A room is an ASCII file, `data/rooms/<id>.txt`. Its id is a number (`2`, `3`, …) or, for a save room, `s` and a number (`s1`, `s2`, …), so the set can grow past twenty-six, and it is the only thing `data/world.json` needs to find the file. Any other id is a load error. Its width and height are a whole number of screens. `grid_pos` in `data/world.json` is the screen cell of the room's top-left corner. The room occupies every screen cell in its rectangle. Two rooms may not occupy the same screen cell.

| Character | Meaning |
| --- | --- |
| `#` | Solid. Rows of `#` merge into rectangles, so cell edges do not snag the player. |
| `.` | Empty. |
| `X` | An exit opening. It has to sit on the room's outer edge, and not on a corner. An opening that crosses a screen boundary is split into one exit per screen. |
| `P` | Where the player starts, the first time, in the start room. Also a standable mark used when entering, and where the player is put when a room is started in directly. |
| `~` | A cell that refuses an Imprint. Open air otherwise, and not drawn. |
| `^` | Spikes. Not solid: the player can walk into them, and dies. |
| `-` | A moving platform's track, side to side. Open air. See Moving platforms. |
| `\|` | A moving platform's track, up and down. Open air. |
| a letter or digit | A thing named in the room's legend. See below. Open air. |

Every glyph lives in one table, `src/world/tiles.gd`. A character that is not in it is a load error, not an empty cell. Every cell on a room's outer border has to be `#` or `X`, so the player cannot walk out of the world. Load collects every problem it finds (`WorldData.errors`) instead of stopping at the first. `tools/validate.sh` prints them and exits non-zero, and a debug build lists them on screen.

**Doors are the openings that face each other.** The destination of an exit is the room that occupies the neighboring screen cell. That exit pairs with the one opposite-edge opening whose span overlaps it. Load reports an error if a neighbor exists and the match count is anything other than one. An empty neighbor is allowed: an opening with nothing on the other side is sealed to solid wall at load, and opens up on its own once a room is placed there.

Each opening is a specific door. A room can have more than one. "A distinct entrance and exit" means each opening is that paired door, drawn on the map, and not a generic "any left edge leads to the room on the left."

Every opening that is left gets a halo: a dithered half-disc of light in the gap, with a pulse, so the way out reads before the player touches it. A sealed opening is plain wall and has none.

**Crossing.** Touching an exit pauses input and builds the next room at `grid_pos × 320×180`. Rooms share world coordinates, so the player does not change place: they keep their height along a side wall, or their column along a floor or ceiling, and are pushed just far enough into the next room to clear the far door's trigger (about 20 px past the wall). If the two doors are not level, the player is carried along the wall into the far door's span. If a wall is right behind the far door, the push is shortened. The camera slides to the view at that entry over about 0.5 s, ease in and out, and then the old room is freed and control returns with the velocity the player had at the door. Only the current room is in the scene, plus the next one during the slide, so a larger world does not cost more per frame.

An **up** door lifts a slow player: they leave it rising at 180 px/s at least, so touching a ceiling door near the top of a jump does not stall in the doorway. A **down** door drops them in with whatever speed they had.

**Blocked doors.** A room can hold its doors shut until a condition is met (see Exit rules below). While it does, each doorway is filled with a **block**: a solid frame around a checker of pixels, drawn where the halo would be. The block is solid and does not change rooms. There is no halo. When the condition is met the blocks shatter and the halos appear at once, and the player can leave.

**Dying.** Touching spikes, or leaving the room's outline by more than 60 px, shatters the player into a burst of pixels for about 0.6 s, and then, if they have health, spends one pip and puts them back on the last safe floor. With none left they go to their save room instead (see Health and save rooms). A moving platform that pushes the player into a wall crushes them, which is a death like spikes. A floor is safe if the player stood on it, it is the room's own floor, and it is not within a cell of spikes or within two cells of a doorway. A moving platform is never safe floor, because it will have moved. An Imprint is never safe floor either, because it breaks: standing on one over spikes and dying brings the player back on the real floor they stood on before, not in the air where the platform was. The safe floor can be in the room before: dying right after a door puts the player back through it. Spawning in a room also counts as a safe floor.

The last eight stretches of floor are remembered, for a death that has health to spend. If the player dies again before standing anywhere after a respawn, that respawn spot was no good and they go back one stretch, so a bad spot can cost one extra death and never a loop.

During the slide the camera is not following. It is on the tween. Afterward it follows again.

Solids are drawn in one chunk per screen, clipped to that screen, so a room several screens wide does not redraw geometry the camera cannot see. The player collides with every solid in the room, drawn or not, so it can land on a platform that is just off screen. Touching a door is a box overlap tested every tick.

### Health and save rooms

**Health** is a count of pips. The player starts with none. A pip is a pickup, and none exists yet: the pickup, how many a player can hold, how they show, and whether a save room refills them are not decided (see Not decided). What is built is the count and what dying does with it:

- With one or more pips, dying spends one and puts the player on the last safe floor, as above.
- With none, dying sends them to their **save room**: onto that room's machine, a plain placement with the old safe floors forgotten, because they may be in rooms the player will not reach again. Nothing is undone. Pickups, tokens and 3TM fills taken since stay taken, and only the player's place changes.

A **save room** has an id of `s` and a number (`s1`, `s2`, …), a file `data/rooms/s<n>.txt`, and exactly one `save` thing in its legend, the save machine. It holds nothing else but platforms: no pickup, token, 3TM or spikes, so a player in a save room is never being asked to do two things. No other room may have a save machine. Entering a save room, by a door or by a warp, makes it the player's save room, and only the latest one counts. Before they have entered one, a death with no health goes to the start room's `P`.

The **save machine** is a sphere split into two halves, hinged at the bottom and standing open in a V, about 25 pixels wide. It is shaded all over with close horizontal lines, one on every other pixel row, so it is shaded with lines and not with dots: the doors' halos are dithered, and the machine must not look like one. The lines stay level on screen when the halves swing open, because tilted lines that close together break up into a checkerboard. It is 3 x 3 cells like a 3TM, and its glyph marks the middle of the bottom row. Round it is a **zone**, one more cell each side, so 5 x 3 cells of open air, with an invisible edge: a player who enters the zone starts a save. The five cells under the zone have to be solid, because the player is popped out onto one of them and comes back to the middle one. It is not solid itself, and the player walks in front of it.

- Entering the zone takes control from the player for `SAVE_TIME` (1.2 s) and does these in turn: they hop on an arc into the middle of the sphere (`HOP_TIME`, 0.2 s); it closes round them (0.1 s); the flag `save:<id>` is set, the room's exit rule is checked, the game saves, and a line at the top says "Game saved"; it spins once, a seam sliding round the ball (`SPIN_TIME`, 0.6 s); it opens (0.1 s); and they are popped out on an arc to the floor on **the other side** from where they went in (0.2 s). Everything is pixels on or off, and nothing fades.
- **It works once each time the room is entered.** Afterwards it closes again and stays a closed sphere until the room is left, so the player can see it is done, is never stopped twice, and is never left unsure whether they saved. Going out and coming back in finds it open again.
- A player put inside it by a respawn or a reload is put in the closed sphere, which spins as it does for a save (0.6 s), then opens and pops them out to the right, about 0.9 s in all. It does not save again, and counts as used for this visit. On a machine not used yet (a save room that was only entered), it saves first, as above, and then lets them out.
- `exits: saved` holds a room's doors shut until its save machine has been used. The first room, `s1`, does: the player has to save before they can leave, which is why a death with no health brings them back there.

### Exit rules

A room's header can carry a line `exits: <rule>`. The rule says when its doors work. It applies to every door in the room, the one the player came in by included. The rules are listed in `src/world/exit_rules.gd`:

| Rule | The doors work when |
| --- | --- |
| `open` | always. This is what a room with no `exits:` line has. |
| `pickups` | every pickup and token in the room has been taken. |
| `saved` | the room's save machine has been used. |

`exits: pickups` in a room with nothing to take is a load error, because it would never mean anything. Neither the 3TM nor a save machine counts as something to take. A rule is tested when the room is built and again each time the player takes something in it, so reloading a save in the middle of a room puts the blocks back or leaves them gone as the flags say. Adding a rule is a line in `RULES` and a case in `ExitRules.met`.

The header holds `exits:`, `legend:` and `trap:` in any order. `trap: allowed` is described under Checking rooms; it is for a room that is a dead end on purpose.

```
exits: pickups
legend:
  T = token id=r2_token
---
```

### Things in rooms

A room file may start with a **legend**: the line `legend:`, lines of `G = kind key=value ...`, and a line of `---`, before the grid. Each legend line gives a glyph one thing to stand for, and the glyph is drawn once in the grid. A moving platform is the one exception: its glyph is drawn as a row, as wide as the platform.

```
legend:
  U = pickup id=r2_imprint upgrade=imprint
---
```

The glyph must be a letter or digit that `Tiles` does not use. Every legend problem is a load error with the room and the line: an unknown kind, a missing or misspelled setting, an upgrade or value that does not exist, a glyph drawn zero or two times, a glyph in the outer wall, a legend with no `---`. `id` is required on every thing. It is written in the file, never derived from position, so a room can be redrawn without losing what the save remembers. Ids are unique across the world.

The kinds are listed in `src/world/entities.gd`, with the settings each needs. There are five: `pickup`, `token`, `machine`, `save` and `platform`. Adding a kind is a line there, a script in `src/world/entities/`, and a case in `Entities.create` (a platform is built by the room from its path instead). `Room.build` makes the things in a room and leaves out any that the player has already taken.

A **pickup** is a small diamond. Touching it gives its upgrade, shows one line at the top of the screen, and saves. It is gone from then on. What it gives is looked up in `data/upgrades.json`: each upgrade is a name, the ability it changes (`stat`), and a `kind`. A `max` upgrade raises a number and never lowers it, so finding a smaller one late does nothing. An `add` upgrade gains a named effect, once.

A **token** is a solid white diamond that bobs, where a pickup is hollow. Touching it puts it in the player's pocket. The player carries at most three. Touching a token with three already carried leaves it where it is and shows "You can carry 3 tokens", once for each time the player steps onto it, and it can be taken once there is room. A token that has been taken stays gone, even after it has been spent. A token has no settings besides its `id`.

A **3TM** (3 token machine, kind `machine`, settings `upgrade=` and `value=` like a pickup) is a square with a rectangle on top. The rectangle has three diamond-shaped openings. It fills 3 x 3 cells and the legend glyph marks the middle of its bottom row, so a 3TM standing on the floor has its glyph in the cell above the floor. Its 3 x 3 cells have to be open air, and it is not solid: the player walks in front of it.

- Touching it with no tokens shows how full it is ("2 of 3 tokens").
- Touching it with tokens takes them all, one at a time. Each leaves the player's body, flies in an arc with a trail to the next empty opening, and fills it with a flash and a burst of pixels. The player cannot move meanwhile. An Imprint platform does not age meanwhile either.
- Filled openings stay filled, and the count is saved, so a player can bring one token now and two later.
- When the third opening fills, the machine shakes and flashes three times and a spark flies from its mouth to the player. The upgrade is then given, with the usual line of text at the top of the screen.
- After that the machine is **spent**: its outline turns dotted, and touching it does nothing. A second upgrade needs a second machine.

A **save machine** (kind `save`, no settings besides its `id`) is described under Health and save rooms. Its 5 x 3 zone has to be open air and the five cells under it solid. A room with an id that is not `s` and a number cannot have one, and a save room has to have exactly one and nothing else but platforms.

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

### Moving platforms

A moving platform slides back and forth along a straight track, side to side or up and down, at a set speed, and waits a moment at each end. Otherwise it is a platform like any other: white, solid on every side, stood on, bumped from below, walked into.

It is drawn in the room as a row of its legend glyph where it starts, as wide as it is, with its track drawn on from one side of it to where it turns: `-` from one end of the row for side to side, or rows of `|` across its columns above or below it for up and down. The legend line gives its `id`, its `speed` in pixels a second, and its `pause` at each end in seconds (0.2 if left out):

```
legend:
  L = platform id=r8_lift speed=60 pause=0.2
---
X.....LLLLL--------------------#
```

- **When it moves.** Its clock starts when its room is built, waiting at the end it is drawn at. So every time the player comes in, respawns or reloads, it starts in the same place. Nothing about it is saved. It is worked out from whole physics ticks (`PlatformPath.rect_at`), so the game and the solver put it in exactly the same place.
- **Riding.** A player standing on it is carried by it, and can walk on it as on any floor. Leaving it, by a jump or by walking off the end, keeps only the player's own velocity: a jump straight up goes straight up, and the platform goes on without them. `MovementConfig.inherit_platform_velocity` (in `movement.tres`, off) adds the platform's velocity on leaving instead: a jump from a platform sliding right at 75 px/s then leaves at 75 px/s more to the right, and steering in the air bleeds it off like any other speed. The switch is there to compare in playtesting.
- **Pushing.** A platform that moves into the player pushes them out of its way. One that pushes them into a wall crushes them.
- **What it needs around it.** Every track cell has to belong to a platform. The row above everywhere it goes has to be open air (`.`, `~` or `P`): no wall, spikes, door, thing or other track, so riding it never scrapes the player off, crushes them, kills them or carries them through a door. Nothing may stand in its way, and it has to keep a cell clear of every doorway. A save room cannot have one, because its platforms stand still.
- **Imprint** cannot go on a track or in the row above it, so an Imprint never overlaps a moving platform.
- It is not drawn with its track. The player learns the path by watching it. The checker's renders draw it light blue where it starts, with its track as blue dots.

### Saving

The game saves to `user://save.json` when a room is entered, when a pickup is taken, and when the map is closed after its zoom changed, and loads it on start. The file holds a version number, the room and the position in it, the visited rooms, the abilities, the map's zoom level, the number of tokens carried, how full each 3TM is, the health, the save room, and the flags (one per pickup taken, `pickup:<id>`, one per token taken, `token:<id>`, and one per save machine used, `save:<id>`). The room and position are always the resume point: the machine of the save room the player last entered, or the start room's `P` before they have entered one. Everything else is written as it stands, so a reload keeps every pickup, token and 3TM fill, and puts the player back at the save. Entering an ordinary room no longer moves where a reload starts.

A file that cannot be read, or that a newer version of the game wrote, is moved aside as `save.json.bad` and the game starts new, so it is never overwritten. A save for a room that no longer exists keeps the abilities and the map and starts in the start room. Headless runs and games started with `--room=` or `?room=` never read or write a save. F4 enters an isolated dev session before room selection; later test activity cannot write the normal save. `--new-game` (`?new-game=1`) is the only way to start over: it deletes the save and empties the game's state before anything is placed, so even a reload before the first autosave cannot bring the old game back, and the map's zoom goes back to the middle. A plain reload keeps the save. While `?new-game=1` stays in the address, every reload is a new game. A save from before tokens existed (version 1) is also set aside, because it comes from a world where Imprint was free and its flags mean something else now. A version 2 save is carried over: room 1 became `s1`, so it is renamed in the room and the visited rooms, the machine counts as used (the player had already left), and the save room is `s1`. To change the save's shape, raise `Save.VERSION` and add a step to `Save._migrate`; to give up on older files, raise `Save.OLDEST`.

### The current slice

Nine rooms (the first is the save room s1, and s2 is a second save room), as content, not as the limit of the format. The flow they make: save at the machine in s1 to leave it, take the token in room 2 to leave that, take one more in room 3 and one in room 5, spend all three at the 3TM in room 4 to get Imprint, use Imprint to cross the spikes in room 5 and then the wall in room 6, fall into room 7, and walk left into the save room s2 or right into room 8, a floor of spikes.

```
 s1  2   3          room 2's floor door drops into 5, room 3's floor hole into 4
     5   4          5 and 4 meet at their side doors, 5 and 6 at theirs
 6                  room 6's floor door drops into 7
 7
 7
 7
s2 7 8              7 meets s2 and 8 at their side doors, at the floor
```

- **s1**, the save room, one screen at `(0, 0)` and the start room. Three tiers of platforms, each a running jump apart, and an exit in the right wall. The save machine stands on the middle platform (row 8, col 16) and the room has `exits: saved`, so the door stays blocked until the player has entered the machine's zone and been saved. The zone fills the platform's width (cols 14 to 18). It is the movement test, and the place a player comes back to when they die with no health.
- **2**, one screen at `(1, 0)`. The landing from s1's door, steps down to the right, a hole in the floor (cols 23 to 27) that drops down to room 5, and a door high in the right wall at the end of a ledge (row 9, cols 25 to 30), reached by a jump from the lower platform. It has `exits: pickups` and a token on the first platform, so it cannot be left, by any of its three doors, until the token is taken.
- **3**, one screen at `(2, 0)`. Its two-cell door and entrance ledge line up with room 2 (door rows 7 to 8, ledge row 9, cols 1 to 8), so crossing between them stays level. A hole in the floor (cols 5 to 10, mostly under the ledge) drops down to room 4. A staircase climbs from the first step (row 14, cols 13 to 17) to platforms on row 10 (cols 22 to 27) and row 6 (cols 26 to 29), then back left to the token platform (row 5, cols 18 to 21). The upper platforms are too far right for a jump from the entrance ledge, so the player still has to descend and climb the staircase. Its first step also climbs back onto the ledge, for the way back to room 2.
- **4**, one screen at `(2, 1)`, under that hole. Three platforms step down from under the ceiling door, each 4 cells apart, so the door is a short climb in and a short climb out. The 3TM stands at the bottom left, beside the left door that leads to room 5.
- **5**, one screen at `(1, 1)`, with doors in the ceiling (up to room 2), the right wall (to room 4) and the left wall (to room 6). A pit of spikes 16 cells wide, with a short floor on its left, is too wide to jump. Three platforms climb from the right-hand floor back up to the ceiling door, and a token sits on the middle one. A player standing on the middle platform can cross the pit by putting an Imprint platform in the gap, and can cross back the same way. It is the first room that is open or shut by an ability.
- **6**, one screen at `(0, 1)`, through the door in the right wall of room 5. A hole in the floor is covered on the player's side by a roof and a wall six cells tall, taller than a jump, so a platform put down by the wall is the only way up onto the roof, and from there the player walks off the end into the hole.
- **7**, one screen wide and four tall at `(0, 2)`, under room 6's hole. It is empty: a long fall onto a floor, with a door at the floor at each end of its bottom screen (rows 68 to 70): the left wall to s2, the right wall to room 8. It is marked `trap: allowed`, because nothing in it leads back up yet. A 3TM and a title card that fades in during the fall and out before the landing are planned.
- **s2**, a save room, one screen at `(-1, 5)`, left of room 7's bottom screen. It is empty but for its save machine, which stands on the floor in the middle (row 16, col 16), and a door at the floor in the right wall (rows 14 to 16) back to room 7. Its exits are open, so saving is a choice. It is marked `trap: allowed` like room 7, because its only door leads there; both lose the mark when room 7's way out is built.
- **8**, one screen at `(1, 5)`, right of room 7's bottom screen, the mirror of s2: a door at the floor in the left wall (rows 14 to 16). The first 5 cells inside the door (cols 1 to 5) are clear floor, and spikes cover the rest of it (row 16, cols 6 to 30), so a player who keeps running right dies. Over the spikes is the first moving platform, `r8_lift`: 5 cells wide on row 13, starting at cols 6 to 10 and sliding right 20 cells to the wall and back at 75 px/s, about 2.7 s each way, with a 0.2 s wait at each end. Its top is four cells above the clear floor, a comfortable full jump. It was on row 12 first, five cells up, which is as high as a full jump reaches (row 11 cannot be reached from the floor, and a hop reaches neither row 12 nor row 13). The way back is to step off its left end onto the clear floor as it gets back. It is marked `trap: allowed`, like 7 and s2.

### Starting in a room

For testing, the game can begin in any room: `--room=<id>` on the command line, `?room=<id>` on the web, or F4 while dev tools are available. F4 enters an isolated session. The player is put on that room's `P`, or just inside its first door if it has none. An unknown id is reported and the start room is used.

### Dev playtesting

F2 or the DEV button opens a paused panel with Player, Rooms and Loadouts tabs.
Tools are always available in editor/debug runs. The browser release uses
`?dev=1` (for example `?dev=1&room=8`), and native exports use `--dev`. Without the
opt-in, exported gameplay has no cheat UI. F3 remains the performance readout;
F4 opens room search. This opt-in is convenience, not a security boundary.

A direct dev launch starts fresh progression and does not access the normal save.
Entering from normal play copies current progression and leaves the player where
they are. The panel can set tokens (0–3), nonnegative health, Imprint unlocked,
width, seconds, and active count in either direction. Bounce says “Not implemented.”
Apply commits a validated draft atomically. Resume / Cancel or Escape closes and
discards unapplied edits. Closing keeps the test active, with `DEV · not saving`.
Imprint-setting changes clear placed Imprints; resource-only changes do not.

The room picker opens with every loaded room listed, visited or not, in natural ID
order, and the current room selected. Click a listed room to choose it, or type to
filter the list.
Start test captures current test progression and uses the selected loadout at the
room's normal test spawn. Start fresh test first clears progression. Retry test
restores that original room and captured flags, machine fills, visited rooms,
map zoom and save-room selection, with the latest explicitly applied powers and
resource counts. Later pickups and consumed tokens/health do not rewrite the
selected loadout. A rebuilt scene resets Imprints, effects, motion and platform
clocks, rather than trying to replay a mid-animation frame.

Two optional switches start off. Retry original test on death plays the normal
shatter, then restores the attempt, including its chosen health. Off uses normal
health/death rules. Bypass door requirements removes physical blocks and exit
locks, retaining ordinary transitions and destinations; it sets no flags. Turning
it off recomputes actual requirements and is refused while the player overlaps a
door that would close. It never opens sealed boundaries.

Named loadouts store powers, tokens and health in `user://dev_loadouts.json`,
version 1, independently of the normal save. Selecting stages a draft; Apply uses
it. Save new, Update, Rename and Delete are explicit actions. Loadouts contain no
room, progression flags, machine state or override settings. New fields acquire
current defaults; removed abilities/effects are reported. Invalid or newer stores
remain untouched and failures are shown without stopping the current test.

No test reads, writes, erases or migrates `save.json`, even after a save machine or
with `new-game` also supplied. Save machines say “Test checkpoint set.” End playtest
destroys the test world before normal save access returns, then resumes the normal
save or a fresh normal game if absent. Launch arguments are consumed for this
in-app return; refreshing a URL still containing `dev=1` starts another test.

The panel waits for a busy animation or map to close; a second F2 cancels pending
opening. Map/panel pause ownership prevents one from unpausing the other. Gameplay
input waits for held keys/buttons to be released, and panel clicks cannot place
Imprints. The pointer is visible while editing. Panel styling stays monochrome.

### Checking rooms

A room is not finished when it loads. `tools/validate.sh` also plays the whole world with the movement simulator, starting from the `P` in the start room, and fails if the world cannot be played.

A **ledge** is a run of cells with air above and floor below. From each ledge the solver tries walking off either end, and jumps from every cell with the input held left, none, or right, and the jump held for a tap, a hop, or the full leap. Each try is the same `MovementSim` the player runs. A try that lands on another ledge, or touches a door, is an edge in the graph. A try that touches a door records the body's position and velocity there. `Door.crossing`, the same function the game uses, says where that body appears on the far side, and the solver lets it fall or walk from there to see which ledge it lands on. A body that touches spikes is dead, so a path through them is not a path. A body that falls through a door keeps falling to the bottom of the room it lands in, however tall: room 7 is four screens high.

- **Error:** a room, or a door in a reachable room, that no path from the start reaches.
- **Error:** a door that every body going through it lands on nothing after, because the room beyond has a void or only spikes under it. The check is that some entry lands on a ledge. It does not promise that every entry does, so a shaft can still be hard to climb out of: play it.
- **Error:** a trap, meaning a ledge the player can reach but from which no path leads back to the start. Falling into a pit too deep to jump out of is one. The first version of room 3 was one.
- **Error:** a pickup, token, 3TM or save machine in a reachable room that no sampled path touches. A path that touches it and then dies on spikes still counts, because the pickup was taken. Only paths that start on a ledge are tried, so a pickup that can be taken only by falling through a door onto it is reported as out of reach.
- **Error:** a room whose exit rule is never met. Its doors never work, so everything past it is out of reach and its own floor is a trap.
- **Warning:** a ledge in a room that says `trap: allowed` with no way home, and the door that nobody inside such a room can touch. A room can say it in its header when it is meant to be a one-way drop (room 7 and the rooms s2 and 8 beside it, until room 7's way out is built). It still has to be reachable from the start, and nothing else about it is relaxed.
- **Warning:** a ledge nobody reached. The solver tries a fixed set of inputs, so a ledge it misses might still be reachable by a path it did not think of. Look at the render and decide.

`tools/render.sh` draws each room and the world map to `build/renders/`. Red bars mark unreachable ledges, yellow bars mark traps, and orange marks a door that was sealed. A moving platform is light blue where it starts, with its track as blue dots.

**Moving platforms in the solver.** Each moving platform is a ledge of its own in the graph, named "the moving platform <id>", so the ledge counts include them. The jumps from a ledge near a track are tried with the platform moving, starting at moments spread over its whole trip: every 12 ticks, or every tick it takes to move a cell if that is sooner (`ReachGraph.phases`, 43 moments for room 8). A jump that lands on the platform at any of them is an edge to it. Once on it, the player can ride it to any moment, because nothing is allowed in the row a rider stands in, so the jumps and the walks off either end are tried from every spot on it at all of those moments. Riding sweeps that row, so a pickup standing in it is taken. A moving platform nobody reaches is a warning, like a ledge. Room 8's moments add about 3 s to a cold run, kept by the cache after that. Left out: the Imprint search does not see moving platforms (it puts no Imprint down from one, and its jumps pass through them), and a body falling into a room through a door does not land on one.

**Imprint in the solver.** The solver takes the player's `Abilities`. With Imprint unlocked, a ledge gets extra edges: a player standing there can put a platform down, jump onto it, and jump from it.
- It does not try every platform. From each ledge the usual jumps are simulated once, and a platform is a candidate only where one of those jumps comes down through the top of a cell row, and only if it is a legal place (the same `ImprintRules` the cursor uses) within a jump of something still out of reach. Each candidate is then checked by simulating the jump again with the platform in place. A platform that passes is searched from like a ledge of its own.
- A platform lives `imprint_duration` seconds, so each of the two jumps is cut to half of that less a little spare time. A one second platform crosses nothing.
- A ledge that cannot get home is searched the same way, with the ledges that can as the targets, so crossing a pit one way with a platform and having no way back is still a trap.
- Left out: putting the platform down in mid-air, and using two in a row. A room that needs either is reported as out of reach even if a player could do it. A room that needs the platform in a place the reach check calls out of reach is also not found.

**What a room needs.** `tools/validate.sh` solves with the starting abilities, takes every pickup that solve could reach, solves again with what they gave, and repeats to a fixpoint, when nothing new turns up or the newly reached things do not change the abilities. The number of things in the world makes this finite; if the search ever fails to settle within that bound, validation fails instead of accepting a partial answer. A room, a ledge, or a pickup that only opens in a later round lists the pickups it needs, cut down by dropping them one at a time to a set it still opens with. Example, from the current world: `Room 5: the ledge on row 16, cells 0-4 needs r2_token, r3_token, r4_3tm, r5_token`. Errors come from the last solve, so a room that stays shut even with every pickup is an error. Tokens and 3TMs are part of this. A save machine reached sets the flag that opens `exits: saved`, and gives nothing, so it never changes what a room needs. A token reached is taken. A 3TM reached gives its upgrade if three tokens are taken for it, and several machines are paid in the order of their ids. A room with an exit rule keeps its doors shut in the search until what the rule asks for has been reached, so a room is only open if the player can first do what it asks. The search does not model the carry limit of three (a player who cannot take a fourth token before spending three is not caught), and it does not treat a blocked doorway as a wall for a body falling through a chain of doors. A trap is judged where the player could first be in it, with the fewest abilities, because a player who has not found Imprint yet is also stuck in a place that needs it to leave.

**Speed, and the cache.** A cold run is about 32 s for 9 rooms, and most of it is the Imprint search: each ledge's jumps (about 5 s, 3 of them room 8's moving platform) and, for every platform Imprint could put down, a check that the jump lands on it (about 6 s) and a "leg" of about 40 simulated jumps from it (about 19 s). What the solver works out about a room depends on nothing but the room and the solver, so it is kept between runs in `build/solver-cache/<room>.json`: the jumps from each ledge, and each platform's leg by cell, width and length. A room's file is used only if two fingerprints match: the room's (its grid with the openings that lead nowhere sealed, its doors and where they lead, its things, where it sits, so a neighbour that appears or moves counts) and the solver's (a hash of the code and numbers that decide a jump: `reach_graph.gd`, `imprint_search.gd`, `movement_sim.gd`, `movement.tres`, and the others listed in `SolverCache.SOLVER_FILES`). Change either and that room, or every room, is worked out again. What is not kept is cheap and depends on more than one room: where a door leads, and the search that spreads out from the start. A warm run takes about 8 s, nearly all of it the landing checks, which are not kept. A run after editing one room redoes that room's share. A file that cannot be read is ignored. The tests never read the cache. `tools/validate.sh --no-cache` ignores it too, and prints the same answers.

Threads were tried first and are not used: GDScript's simulation only runs about 1.5 times faster on two or four threads, and slower on eight, so an Imprint search on all cores saved about 15%.

## Camera

The camera shows one screen, and it stays inside the room.

- A room that is exactly one screen locks the camera to the room's center. It never scrolls.
- A wider or taller room follows the player, clamped so the 320×180 view never leaves the room, then rounded to whole pixels.
- The follow target is the player. During a door slide, follow is off until the slide finishes.

## Map

Hold Tab or M. The game pauses. A dim covers the playfield over about 0.1 s, and a panel scales from 0.92 to 1. Releasing the key dismisses it.

Visited rooms are outlined rectangles. The current room is filled. The player is a blinking pixel. Exit gaps break the outline where the doors are, and a connector joins a door to the door it leads to. The connector is drawn once the room on the other side has been visited.

A room that spans screens is one rectangle, not a row of separate rooms. The gap that normally separates neighboring rooms is filled in across the screens that room owns, so the shape on the map matches the continuous space. Door gaps and the player marker are placed per screen, so a door on the second screen sits on the outer edge of that wide rectangle, in line with a one-screen neighbor.

The room layer is drawn into a viewport and redrawn when the current room changes, a new room is visited, or the zoom changes. Each frame after that is the texture plus the marker.

**Zoom.** While the map is held, Up or W zooms in and Down or S zooms out, one level per press, stopping at the ends. There are three levels:

- **Out** shows every visited room, however big the map gets. It never zooms in past Middle, so a small map looks the same at Out and Middle. It is centred on the visited map.
- **Middle** is the view the map always had: centred on the current room, clamped when the map is larger than the panel.
- **In** is twice that, centred on the player's marker and clamped to the map.

The map is redrawn at each scale and not stretched. Every corner is scaled and rounded to a whole pixel, and lines stay one pixel thick, so outlines and door gaps are as sharp at every level and rooms that touched or had a gap keep that. The level is part of the saved game (see Saving), and the map opens at the level the player left it at.

**Legend.** In the bottom-right corner of the map, two rows of symbols and no words, on a small black patch: an up arrow beside a magnifying glass with a plus (zoom in) over a down arrow beside a magnifying glass with a minus (zoom out). A row that can do nothing more, because the map is at that end, is drawn grey.

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

Status: built: finding it (three tokens at a 3TM), placing it, the reach check, the lifetime and its countdown, and the rules below. The solver knows about it, so `tools/validate.sh` proves which rooms are open or shut by it. Width, duration, and multiple active platforms work in the runtime and can be set through dev tools, though current rooms award none of them. Bounce is only a stored effect name; its behavior is not built.

Imprint is the ability that makes Freddy's Fall a metroidvania. The mouse cursor is a platform. The player places it, jumps from it, and uses longer, longer-lasting, and stranger versions of it to open paths that the authored rooms withhold.

### Fantasy

The cursor is a promise of a foothold. Before the click, the player can see whether that foothold is one they can actually reach. After the click, it is real for a few seconds, and then it breaks.

### The platform

The cursor snaps to a cell. That cell is the platform's left edge. The platform is `width_cells` wide and one cell tall. It is never rotated and never placed between cells. It shares edges, heights, and jump distances with the authored platforms, which are about four or five cells wide.

At the start, `width_cells` is 2: the player's width plus one spare cell. The first description of that spare was "one pixel." On this grid one cell is the player, so the spare is one cell.

### Placing

Left click places the platform under the cursor. There is no keyboard or gamepad way to place one, and none planned for now. The code gets the target cell from one function, so another input can feed it later.

- The starting limit is one Imprint: placing another replaces it immediately. `imprint_max_active` already supports larger limits; placing at the limit replaces the oldest platform. No current room awards that upgrade.
- It has to lie fully inside the current room. The room is the whole room, including every screen it spans, not the visible viewport.
- It cannot overlap level geometry, spikes, or a door's trigger zone and the cell around it, so it cannot wall off a doorway or cover spikes.
- It cannot overlap the player.
- A `~` cell refuses it. That is how a puzzle can forbid the obvious ledge without changing the jump rules. `~` cells are not drawn: the player finds one by being refused there.

A platform may sit just above spikes. Bridging a spike pit with a platform a few cells over it, to jump from, is a core puzzle.

A placed platform is solid on every side, like authored floor. It can be stood on, bumped from below, and walked into. When it breaks under the player, they fall.

A legal placement lasts `duration` seconds, 2.5 at the start. The dashed line through it is its clock: it starts with a dash for every pair of cells it is wide (four, at the start), and one dash goes in each equal share of its life, the leftmost first, so at 2.5 seconds one goes every 0.625 seconds. While the last dash is the only one left, the whole platform also blinks, every tenth of a second. Then it shatters into pixel shards. It does not fade out.

### Reach, before the click

The cursor has two looks: a dotted outline of the platform wherever one may go, and a small × where one may not. For now the outline is the same whether or not the player can reach it. (It used to be filled, with a sparkle, when they could. That may come back.)

The game still works out, before the click, whether some jump the player can perform from their current position lands on the platform's top, so the look can show it again without new work.

The check includes being in the air. It starts from the player's real state: on the ground, or airborne with their current velocity. It tries a small set of jumps, not every possible input: hold left, hold nothing, or hold right, and release the jump at a few different times. Those paths use the same movement rules as the player, against the room's solid rectangles. If any path lands on the candidate platform's top, it counts as reachable.

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

The player does not start with Imprint. They earn it. A token lies in room 2, which cannot be left until it is taken, one more lies in room 3 and one in room 5, and the 3TM in room 4 takes all three and gives Imprint. From then on the cursor is a platform, and a line appears across the player's body.

Tokens are the currency for upgrades, and a 3TM is the shop. Tokens are scattered through the world to be found by exploring, up to three at a time in the pocket, which puzzles are built around. Each 3TM is set to give one upgrade, so later upgrades (the ones below) mean placing more machines. How many tokens each costs is three for now.

### Upgrades

Upgrades are pickups in the world, written into a room's legend and drawn with their own character, and kept on the player once collected, and in the save. Leaving a room does not take them away.

| Upgrade | Starts at | Grows to |
| --- | --- | --- |
| Width | 2 cells | 3, then 5 |
| Duration | 2.5 seconds | longer |
| How many at once | 1 | stays 1 unless a later upgrade says otherwise |
| Behavior | a still platform | bounce, and others after that |

Width, duration, and behavior are the three things a room can demand. A later room can need five cells of width, or a platform that lasts long enough to cross two jumps, or a bounce, and the layout is what enforces it. There is no separate key item.

Bounce is the first special behavior. Others can be added the same way: a property of the placed platform, found as a pickup, and required by some later gap.

Upgrades not awarded by current rooms; the first three work in the runtime and can be tried in dev tools:

- A longer platform.
- More than one platform at a time. Placing one then stops destroying the other, up to the count.
- A longer life for the platform.
- A bouncy platform.

The starting values are the defaults in `Abilities` (`src/core/abilities.gd`): width 2, duration 2.5 seconds, one at a time, no special behavior, and Imprint itself locked. They live in `GameState.abilities`, and the width and duration are read when a platform is placed.

### Look

Imprint uses the same black-and-white pixel language as the rest of the game.

- Dotted outline: a platform can go here.
- A small ×: you cannot put one here.
- Dashes going out, left to right: how long a placed platform has left. Blinking with one dash left: it is about to break.
- A placed platform is always drawn over the cursor, so what the player can land on is never hidden by the preview.
- Shatter into pixel shards: it is gone.

The shards are small. They should read at 320×180 and survive the softer palette, because that palette remaps the frame rather than the sprites.

## Implementation reference

How each system is built, with the constants that matter. File names are under `src/`. Where a number is a named constant, the name is given, so a change to the number is a change to that line and to this page.

### Loading a room (`world/room_parser.gd`)

`WorldData` reads `data/world.json` and each room's file, then calls `RoomParser.build(entries, start_room, errors)`. Nothing in the parser touches the disk or the scene tree, so a test can build a whole world from strings. In order:

1. **Per room** (`parse_room`): split the header from the grid at a line of `---` (a header with no divider is an error); read the header (`legend:` lines, `exits:`, `trap:`, each given at most once, every bad line an error with its line number); read the rows (every row the same width, the room a whole number of 32×18 screens); work out `screens`, `pixel_size` and `bounds_cells` (the whole room, not one screen, since an Imprint may go anywhere in it); scan the cells once (the spawn, `~` cells, spikes, glyphs that mean nothing, outer-wall cells that are not `#` or `X`, and where each legend glyph is drawn); check each 3TM's and each save machine's 3×3 cells are open air, and the cell under a save machine is solid; check a save room (`RoomInfo.is_save_room`, an id that starts with `s`) has exactly one save machine and no other room has any; check the exit rule makes sense for the room.
2. **Across rooms:** every room id is a number or `s` and a number (`RoomParser.is_valid_id`); two rooms may not occupy the same screen cell; an entity id may be used in only one room.
3. **Doors** (`_parse_exits`, `_link_exits`): runs of `X` on one edge become doors, split where they cross a screen boundary; an `X` on a corner or off the edge is an error. A door's destination is the room on the neighbouring screen cell. It pairs with exactly one opening on the opposite edge whose span overlaps it (any other count is an error and the door is cleared).
4. **Sealing:** an opening with no room beyond it becomes solid (`_seal_dead_ends`), so `RoomInfo.rows` is the room as played, and room fingerprints see it.
5. **Solids:** `merge_solids` joins runs of `#` into rectangles (a run is merged with the run directly under it when both have the same start and length). The player and the solver collide with these rectangles, never with cells, so there are no seams to snag on.
6. **Start room** must exist and have a `P`.

Errors are sentences naming the room (and the line, for the header). A bad drawing tends to repeat one mistake along a wall, so each kind is capped at `MAX_PER_KIND` (5) per room and the rest counted.

### The movement (`player/movement_sim.gd`, `player/movement_config.gd`)

`MovementSim.State` holds a body's position, velocity, `grounded`, `coyote`, `buffer`, `launched`, `cut`, `riding` (the moving platform it stands on, or -1), and, after a step, `jumped`, `crushed` and the `floor_rect` it stands on. `step(cfg, state, rects, input_x, jump_pressed, jump_held, delta, movers, tick)` does one tick, in this order:

0. With moving platforms (`movers`, which go from where they are at `tick` to where they are at `tick + 1` during the step), `move_with`: the one the body is riding carries it by its move, and any other that moves into the body pushes it out of its leading side, both stopped by walls. A body still inside a platform after that is `crushed`. The platforms are then solid, where they are at `tick + 1`, for the rest of the step.
1. `integrate`: horizontal speed moves toward `input × run_speed` at the ground or air acceleration (or friction when there is no input); the coyote timer is set while grounded and counts down; the jump buffer is set on a press and counts down; if both are above zero a jump starts (`vy = -jump_speed`); otherwise a released jump that is still rising is cut (`vy × jump_cut`, once), and gravity is applied, scaled by `apex_gravity_scale` while `|vy| < apex_threshold` and by `fall_gravity_scale` while falling, capped at `max_fall_speed`.
2. `corner_correct`: a body moving sideways into a block and not rising is lifted up to `corner_correction` px if that clears it; a rising body that clips a ceiling corner is pushed sideways by up to the same. Both look ahead with a blocked test and never move through a block.
3. `resolve`: move on x, push out of any block it overlaps; move on y, push out, and `grounded` is set when it came down on a block. `riding` is the moving platform whose rect is the floor, or -1. A body that was riding and is now in the air gets the platform's velocity added only if `inherit_platform_velocity` is on.

The body is `HALF` = 5 px either side (a 10×10 box). `standing(position, rects)` is a probe one pixel down. `simulate_jump(...)` repeats `step` at a fixed 1/60 s from a start position and velocity until the body lands (grounded after leaving the ground, past tick 2), touches a trigger rect (a door), touches a hazard rect (it died), leaves `bounds`, or runs `limit` ticks (180 by default). It returns the final position and velocity, `landed`, the floor rect, `trigger` (the index touched or -1), `hazard`, the `collected` indices among rects passed as `collect`, the tick count, and, with `record`, the whole path. `later_input` and `switch_frame` change the steering part way through. `movers`, `start_tick` and `start_riding` run it with moving platforms: a crushed body counts as a hazard, and the result's `riding` is the platform it landed on. Everything that needs to ask "what would the player do" calls this. The player's own node calls `step` with the real input and `delta`.

### Doors in play (`world/door.gd`, `world/room.gd`, `world/world.gd`)

A door's **trigger** (`Door.trigger_rect`) is its opening plus 4 px of the room beside it. `Room.touched_door` tests the player's box against it every tick, and returns nothing while the room is locked or a slide is under way. The solver tests simulated paths against the same rectangle.

`World._on_exit` runs a crossing: the world goes busy and the player freezes, with their velocity kept aside; the next room is built and placed at its `grid_pos × 320×180`; `Door.crossing` says where the player appears and with what velocity; the camera tweens to the new room over `TRANSITION_TIME` (0.5 s, sine in and out, stepped on physics time); then the old room is freed, the kept velocity is given back, and the game autosaves. `Door.crossing` keeps the place along the wall (clamped into the far door's span) and tries pushes of `CLEAR` (19.5 px), 15, 10, then 5 px into the room, taking the first that is not inside a wall. Going up it raises the upward speed to at least `UP_BOOST` (180 px/s). The solver calls the same function, so it lands bodies where the game does.

### Blocked doors and exit rules (`world/exit_rules.gd`, `world/room.gd`)

`Room.build` sets `locked = not ExitRules.met(info, flags)`. A locked room puts a `DoorBlock` in each doorway instead of a halo. The blocks are in `Room.world_rects()` (so the player collides with them) and not in the private floor list used to judge safe floor. Taking something calls `World._collect`, which calls `Room.recheck_exits(flags)`: if the rule is now met the blocks shatter, halos appear, and `exits_opened` fires; `World._on_exits_opened` then calls `ImprintTool.sync_solids()` so the player's collision list stops including the blocks. Nothing is stored about the blocks: the flags decide them each time the room is built, so a reload puts them back or leaves them gone correctly.

### Things in rooms (`world/entities.gd`, `world/entities/`, `world/world.gd`)

`Entities.TYPES` lists each kind's required and optional legend keys; `Entities.problems` turns a bad legend line into sentences. `Room.build` skips anything `Entities.present(def, flags)` says is already taken and builds the rest with `Entities.create`. The player touches things by box overlap each tick (`Room.touched_things`), and `World._collect` decides what that means:

- a **pickup** calls `GameState.collect` (set `pickup:<id>`, apply the upgrade), toasts the message, and the thing leaves;
- a **token** is taken if the pocket has room (`GameState.TOKEN_CAP` = 3), sets `token:<id>`, and leaves; with a full pocket it stays and says so once per visit (`noted`, cleared when the player steps off it);
- a **3TM** runs `World._feed`, a coroutine: the world goes busy; for each carried token (until the machine is full) a `FlyingToken` arcs from the body to the next slot over `FEED_TIME` (0.45 s), the slot fills and `GameState.machines[id]` is updated, then a pause of `FEED_PAUSE` (0.2 s); when the third slot fills the machine dispenses (about 0.8 s of shaking and flashing), a spark flies to the player over `SPARK_TIME` (0.3 s), and `GameState.grant` applies the upgrade; then control returns and the game autosaves. A machine is spent when `filled >= TokenMachine.COST`.

- a **save machine** runs `World._save_at`, a coroutine, when the player enters its zone (`SaveMachine.rect`, 5 x 3 cells) and `used` is not set: the world goes busy and the player is held (`_hold_player`); `_arc` moves them on a parabola to `SaveMachine.centre` over `HOP_TIME` (0.2 s) and they are hidden; `SaveMachine.close` shuts the halves (0.1 s); `_commit_save` sets `save:<id>` and `GameState.save_room`, runs `recheck_exits` (so `exits: saved` opens), autosaves and toasts "Game saved"; `spin` turns it (0.6 s); then `_pop` opens it (0.1 s), arcs the player to the floor two cells to the side opposite the one they entered from (0.2 s), places them there with the room's current solids, returns control, and starts the machine closing without waiting. `used` is on the node, and the room is built again on every entry, so a new visit finds the machine open. A body in the machine's 3 x 3 when it is built by a reload (`World._ready`) or a death with no health (`_respawn`) is found by `Room.save_machine_holding`, and `_emerge` shuts the machine round it, saves first if the flag is not set, spins it, and runs `_pop` to the right. `SaveMachine.pixels` is the one-bit drawing (two half discs swung about the hinge, or a ball with lines of longitude; both are filled with level lines every `LINE_STEP` (2) rows by `_shade`), and `touch_rect_for` is the zone, which the solver uses too.

After any take, `recheck_exits` runs and the game autosaves.

### Moving platforms (`world/platform_path.gd`, `world/movers.gd`, `world/entities/moving_platform.gd`)

The parser turns a `platform` legend glyph into a `PlatformPath` in `RoomInfo.platforms` (`_place_platform`, `_track_length`), and checks the rules around it (`_check_platforms`, and `_check_platform_doors` once the doors are known). A path holds the drawn cells, the direction, how many cells it travels, `travel_ticks` (its distance over its speed, at `TICKS_PER_SECOND` = 60) and `pause_ticks` (`DEFAULT_PAUSE` = 0.2 s). `period()` is a trip there and back with both waits. `rect_at(tick)` waits, slides linearly, waits and slides back. `swept_cells()` is every cell it covers, `band_cells()` the row above that, and `keep_out()` both, in pixels. `Movers` is a room's paths shifted to where the room is.

`Room.build` makes a `MovingPlatform` node for each path and a `Movers` at the room's position. The room runs at `process_priority` -1, so each physics tick it advances its `tick` and moves its platforms before the player steps. The player keeps the `room` the world placed it in, and steps with `room.movers` and `room.tick - 1`, so it is carried from where the platforms were to where they are now. A held player (a door slide, a save machine, a 3TM, a death) is not stepped, and stops riding. `World._physics_process` treats `Player.crushed()` like spikes. `Room.mover_rects()` gives the platforms where they are now, which the Imprint preview adds to what it checks a jump against.

### Dying and safe floor (`world/world.gd`, `world/room.gd`)

Touching spikes, or leaving the room's outline by 60 px, calls `_die`: the world goes busy, platforms are cleared with shards, the player shatters, and after `DEATH_TIME` (0.6 s, on physics time) `_respawn` puts them back. `_die` decides where: with `GameState.health` above 0 it spends a pip and `_respawn` puts them on the last safe spot, as described below; with none, `_respawn` calls `_place_in` at `_resume_point()`, the machine of `GameState.save_room` (its `RoomInfo.save_cell`) or else the start room's `start_position()`. That placement clears the safe floors. `GameState.save_room` is set when a save room is entered (in `_place_in` and in `_finish_transition`) and when a machine is used. The world keeps `SAFE_HISTORY` (8) stretches of floor. Each entry is a room and a position, and a new position within `SAFE_SPACING` (30 px) of the stretch's start updates that entry instead of adding one. A spot is recorded when the player stands on the room's own floor (not an Imprint, not a door block) with no spikes within a cell to either side and no door within two cells (`Room.is_safe_spot`). If the player dies again before standing anywhere new after a respawn, that spot was no good and the newest entry is dropped first.

### Saving (`autoload/game_state.gd`, `autoload/save.gd`)

`GameState` holds what a save holds: `visited` (a set of room ids), `abilities`, `flags` (`pickup:<id>`, `token:<id>`, `save:<id>`), `tokens` carried, `machines` (id → tokens inside), `map_zoom`, `save_room` (an id, or `""`) and `health` (0 or more). `to_dict` and `load_dict` are the only two places that know the shape, and `load_dict` clamps and defaults everything, so a damaged file gives a smaller state and not a crash. `Save.write(room, position)` adds `version`, `room` and `position` (room pixels) and writes `user://save.json`. `Save.load_game()` returns where to put the player, or `{}`. `VERSION` is 3 and `OLDEST` is 2 (`_migrate` carries a version 2 file over: room `1` becomes `s1`, `save:s1_save` is set, the save room is `s1`): a file older than `OLDEST`, newer than `VERSION`, or not valid JSON is renamed `save.json.bad` and the game starts new. `Save.enabled` is independently off in headless runs. `DevSession.isolated()` also guards `write`, `load_game` and `erase` during room/development tests. Ending a test never changes the independent disable flag. A save written before a field existed loads with that field at its starting value, which is why changing a starting number (Imprint's duration) does not reach old saves.

Writes happen on entering a room, after a pickup, token, 3TM or save machine, and when the map is closed after the zoom changed (`World.save_now`). Every write puts the resume point (`World._resume_point`) in `room` and `position`, whatever the player was doing, and the rest of the state as it stands.

### Dev implementation (`dev/`, `ui/dev_panel.gd`)

`DevSession` is an always-processing autoload with normal, room-test and dev-test
modes. All cheats pass through its validated methods; the UI never mutates game
progression directly. `apply` patches only edited fields, updating both live
values and the separately selected retry loadout. `capture`, `start` and `retry`
keep deep-copied dictionaries; `_replace` frees the old world before attaching
the rebuilt one. `end` also frees it before restoring normal save access.

`DevCatalog` is pure: it generates/deduplicates controls by stat from each
upgrade's `dev` metadata, validates exact values, overlays loadouts on captured
progression, and reconciles older loadouts into drafts. Metadata types are `bool`,
`int`, `float`, `effects`, or `unsupported` with a reason. Numeric metadata declares
bounds, step and units; effects declare `implemented` and `planned`. Integer edits
are bounded to 2147483647 for representation safety. Imprint duration accepts
0.01–1000000 seconds, a dev-input bound, not a gameplay progression limit.
`RESOURCES` covers tokens and health, and coverage tests match the real token cap.
`DevLoadouts` validates its version/entries and writes by temporary-file replacement.
It publishes memory changes only after successful persistence.

The world coordinates map/dev modal pause ownership and release-gated gameplay
input. Runtime rooms receive an explicit door override; `ExitRules.met` and the
solver continue to evaluate real progression. Both opening and closing door
refreshes rebuild physical blocks/halos and synchronize player/Imprint collision.

**Every gameplay feature includes dev support in the same PR.** Register its stat,
serialization and dev metadata; implement exact setting/removal/reset, loadout and
retry compatibility, and tests. New resources/actions use the common catalog or
session controller. Unsupported mechanics require an explicit reason, and planned
effects stay disabled. `dev_catalog_test` rejects unregistered upgrades, stats and
ability properties. New room IDs appear in the picker automatically. This rule
also lives in `AGENTS.md` so future agents cannot treat cheats as optional cleanup.

### The camera (`core/grid.gd`, `world/world.gd`)

`Grid.camera_focus` centres a one-screen room, and otherwise follows the player clamped so the 320×180 view stays inside the room, rounded to whole pixels. The camera has no smoothing and no interpolation. During a door slide it is on a tween and not following.

### Imprint in play (`imprint/`)

`ImprintTool` is a `Node2D` child of the world, with interpolation off and drawing in world space. It is active when Imprint is unlocked, the player is in control, a room is current, and the world is not busy.

- **Placing** (`place`, on the `imprint` action): the cell under the cursor is the platform's left end and it is `imprint_width` cells wide. `ImprintRules.check` refuses, in this order, with the reason: outside the room, on solid, on spikes, within a cell of a door's trigger, on a `~` cell, overlapping the player, overlapping another platform that will survive. Platforms newer than the limit (`imprint_max_active − 1`) survive; older ones shatter. A placed platform is a rectangle added to the player's collision list by `sync_solids` (the room's rects plus every platform), which is also called when one expires and when a room's doors open.
- **Ageing:** each platform's `age` grows by the physics delta unless the world is busy (a door slide, a death, a 3TM feed). At `lifetime` it shatters and `sync_solids` runs. Leaving a room, dying, and warping clear them (`clear`).
- **The clock** (`ImprintPlatform`): `_line_xs` gives the dashes (one 2 px dash every 4 px, starting 2 px in, while 2 px fit before the end, so a 2-cell platform has four). `lines_left()` is `ceil(total × (lifetime − age) / lifetime)`, so one dash goes in each equal share of the life, the leftmost first. `blink_time()` is `lifetime / total` (the last dash's share), and `blinked_off()` is true for every other `BLINK_PERIOD` (0.1 s) while `age > lifetime − blink_time()`.
- **The preview:** `_update_preview` recomputes only when the key (cursor cell, player cell, on the floor, width, platform count) changes. It sets `_state` to unavailable (a rule refused it), unreachable, or reachable (`ImprintReach.can_land_on` found a jump). `ImprintReach` tries input left, none and right, with the jump held for `HOLDS` (3, 8 or 90 ticks) or, from the ground, not jumped; and plans that go straight and steer `STEER_AT` ticks later. A path counts if it lands on the platform's top (within 0.6 px, overlapping it by more than 0.5 px) and does not touch spikes or a door. Its window is `REACH_X` 170, `REACH_UP` 70, `REACH_DOWN` 400 px. The look ignores reachable versus unreachable for now (both are the dotted outline).
- **Drawing:** the preview first, then the placed platforms, so a platform is never hidden by the cursor. The operating system's cursor is hidden while the tool is active.

### The solver (`world/reach_graph.gd`, `world/imprint_search.gd`)

The solver answers "can a player get here, and get back", using `MovementSim` and no scene. It is used by `tools/validate.sh` and the tests only.

- **Ledges.** A ledge is a run of standable cells on one row (air, spikes-free, with solid below). `lo` and `hi` are the range a body's centre can have while still on it: a body hangs on until its centre is half a cell past the end, unless a wall or spikes are right there.
- **Edges.** For every ledge, `_ensure_edges` simulates: a jump from the left end, every cell centre and the right end (`start_xs`), with input left, none or right (running only if there are `RUN_UP` = 5 px of ground behind it), and the jump held `HOLDS` = 3, 8 or 90 ticks; and walking off either end. `try_plan` simulates for `limit` ticks (`frame_limit`, 180) against the nearby solids (`near_solids`: ±`REACH_X` 170, up `REACH_UP` 100, down `REACH_DOWN` 400). A path that lands on another ledge is an edge; one that touches a door records a `Touch` (door, position, velocity; two touches within 10 px and 45 px/s are one); one that touches a pickup, token, 3TM or save machine records it, even if it then dies on spikes; one that touches spikes is dead and counts for nothing else. A ledge that runs into a door's trigger walks into it.
- **Doors.** A touch lands where `Door.crossing` puts the body, and `_land` finds what it comes to rest on: standing on something, or falling with input left, none and right for up to `FALL_LIMIT` (300 ticks, so a four-screen drop lands) through the near solids down to the bottom of the room, or through another door, up to `MAX_CHAIN` (3) in a row. Results are cached per touch.
- **Flooding.** `analyze` starts at the start room's spawn and floods along the edges (`_flood`). A room whose exit rule is unmet is **locked**: the door touches of its ledges are held until `_open_locks` finds the rule met by what the run has reached (`ExitRules.met` with flags built from reached things), then released. `_settle` repeats flood, Imprint search and unlock until nothing changes.
- **Imprint.** With Imprint unlocked, `ImprintSearch.expand(ledge, targets)` adds edges from a ledge by one platform put down from it (see below). The edges are kept in the run (`extra_to`, `extra_touches`, `extra_pickups`) and flooded like any other.
- **Home.** `_home` walks the edges backwards from the start; a reached ledge not in it is a trap. For ledges with no way home with Imprint unlocked, `_place_imprints_to_get_home` searches again with the ledges that are home and the doors as targets. In a `trap: allowed` room a trap is a one-way warning instead.
- **The report** (`Report`): `errors` (a room, door, pickup or exit rule that cannot be reached; a door that lands nowhere; traps), `warnings` (ledges nobody reached, one-way ledges and doors nobody inside can touch), counts, `pickups`, `needs`. Lines are capped at `MAX_LINES` (6) per kind.
- **Progression** (`solve`): solve with the starting abilities; take every pickup, token and 3TM reached; give the abilities those make (`_with`: each pickup's upgrade, and each machine's upgrade if tokens can pay `MACHINE_COST` = 3 for it, machines paid in id order); solve again until nothing new is reached or the abilities stop changing. `taken` only grows, so `_things.size() + 1` analyses are enough for every thing to be discovered one round at a time and for one final pass with the last upgrade applied. Exhausting that safety bound is an error, never a partial successful report. `needs` for a room, ledge or pickup is the set of things taken before the round it first opened, cut down by dropping one at a time (`_needs`). Errors come from the last solve; a trap is judged in the first round it appears, with the fewest abilities.
- **`ImprintSearch`** keeps three caches: `_arcs` (each ledge's jumps, recorded tick by tick), `_legs`, and the graph's `_landings`. `expand` takes the arcs of a ledge; wherever a falling arc crosses the top of a cell row, the platforms of `width` cells that arc would land on are **candidates**, if `ImprintRules` allows them and one of the targets is within `REACH_X`/`REACH_UP`/`REACH_DOWN` of standing on them (at most `MAX_CANDIDATES` = 600 per ledge, and `MAX_ARCS_PER_CANDIDATE` = 6 arcs each). Each candidate is checked by re-simulating its arc with the platform in place (`_lands_on`). A candidate that passes gets a **leg**: it is treated as a ledge of its own (`_compute_leg`: about 40 simulated jumps and walks from it) and what it reaches is merged in. A leg's tick limit is `clamp((duration × 60 − SPARE_TICKS) / 2, MIN_LEG, 180)` (55 ticks at 2.5 s): each of the two jumps gets half the platform's life less 40 ticks to spare. Legs are keyed by cell, width and limit.

### The solver's cache (`world/solver_cache.gd`)

`ReachGraph.cache` is empty by default (the tests solve from scratch). `tests/validate.gd` sets it. `SolverCache.entry_for(info)` loads `build/solver-cache/<room id>.json` if its `format`, `solver` and `room` fields match; the entry holds `edges` (every ledge's reach, by index) and `legs` (by `x|y|width|limit`). `_ensure_edges` and `ImprintSearch._leg_of` read an entry before simulating and store what they simulated; `save()` writes the entries that changed. The solver fingerprint hashes `FORMAT` and the text of every file in `SOLVER_FILES`; the room fingerprint hashes the id, position, size, spawn, exit rule, trap flag, the rows (as sealed), the doors (edge, rect, screen, destination, far rect), `~` cells and every thing (type, id, cell, settings). A file that cannot be read, or that does not match, is ignored and rewritten. Not cached, because they are cheap and depend on more than one room: where a door lands a body (`_landings`), and the flood itself. `validate.gd` prints how much came from the cache.

### The map (`ui/map_overlay.gd`, `ui/map_view.gd`)

`MapOverlay` is a `CanvasLayer` (layer 10, process mode always). Holding `map` pauses the tree (it remembers that it did so, and unpauses only when the fade-out ends), fades a dim in over about 0.1 s, and scales a 256×148 panel from 0.92 to 1. The panel holds a 240×132 `SubViewport` texture (`VIEW_SIZE`) with a `MapLayer` in it, a `Marker` and a `Legend` control on top.

- **Map units:** one pixel per cell, a screen being `ROOM_PX` 32×18 and neighbours set `STRIDE` 40×26 apart, so there is an 8×8 gap between rooms. A room of several screens is one rectangle (`room_rect`).
- **Drawing:** visited rooms are outlined (gaps where doors are), the current one filled grey (an opaque grey: a translucent white is premultiplied twice in the web build and vanishes), and connectors drawn to visited neighbours. It redraws, rendering the viewport once (`UPDATE_ONCE`), when the room changes, a room is visited, or the zoom changes.
- **Zoom** (`MapView`, pure statics): `scale_for(level, bounds, view)` is `min(1, view / bounds)` for Out, 1 for Middle, 2 for In; `scaled_rect` scales both corners and rounds them, so lines stay one pixel and neighbours keep their gaps; `view_center(focus, bounds, scale, view)` picks the point at the window's centre (clamped to the visited bounds when the map is bigger than the window, rounded to a pixel). `refresh()` focuses on the visited map (Out), the current room (Middle) or the player (In). `MapLayer` is **moved** to `view/2 − view_center`; a `Camera2D` here only moves in the physics step, after the one frame the viewport renders for a change, so it showed the previous zoom's view.
- **Keys:** while open, `map_zoom_in` and `map_zoom_out` (just pressed) step the level and stop at the ends. `GameState.map_zoom` is the stored level. Closing the map after a change asks the world to save (`save_now`).
- **Legend** (`MapView.legend`): two rows, each an arrow and a magnifying glass drawn from 5- and 7-pixel pictures, on a black patch 1 px from the bottom-right corner. A row that can do nothing is grey.

### Effects and small parts

`ExitHalo` is a dithered half-disc of 12 pre-painted 64 px frames, played as a pulse. `Shatter` is 14 square shards that fly out and fall for 0.5 s; nothing fades. `Toast` (layer 15) shows a line for 2.5 s. `FlyingToken` arcs 16 px high with a trail of 6 recent positions, every other one drawn. `InventoryMarks` cuts black plus-shaped 3×3 marks out of the body at (4,2), (2,4) and (6,4) for tokens one to three, and a line on row 8 from column 1 to 8 once Imprint is unlocked. `SaveMachine` draws a pixel ring (outer radius 13 px, the band from 8 px lit a segment at a time) around a hole of 4 px, on a 12 px base, with no antialiasing. `DebugOverlay` (layer 20) shows F3's readout and debug load errors. `DevPanel` (layer 30) owns F2/F4 and the paused playtest UI.

### What the solver and the preview do not model

- Placing a platform in mid-air, and using two in a row. A room that needs either is reported out of reach.
- The carry limit of three tokens, and a blocked doorway as a wall for a body falling through a chain of doors.
- Paths other than the fixed plans (the inputs and holds above), so "unreachable" can mean "a plan it did not try". That is why an unreached ledge is a warning and an unreached room, door or pickup is an error.
- A ledge's `MAX_CANDIDATES` cap, and `REACH_*` windows: a platform beyond them is not tried.
- Moving platforms in the Imprint search, and a body coming through a door landing on one. A moving platform is only tried at the moments `ReachGraph.phases` picks, so a jump that works only between two of them is not found.

## Decision log

What was decided, in the order it came up, with the reason. Pull requests are named by number.

**The world and the data**
- **Rooms are ASCII files, ids are numbers, rooms are whole screens.** Easy to write from a drawing, easy to diff, and a room is checked by the same code that plays it. Every rounding made when translating a drawing is reported to the user.
- **`grid_pos` in `world.json`, doors inferred from facing openings.** No hand-written door table to disagree with the map. An opening with nothing beyond it is sealed until a room is placed there.
- **Legend ids are written in the file and never derived.** The save remembers things by id, so a room can be redrawn without losing what the player did.
- **Errors are collected and reported, never thrown.** A bad room should tell its author everything wrong with it at once.

**Movement and the player**
- **The player is a `Node2D` with a box and no physics body; all movement is `MovementSim`.** The solver, the Imprint preview and the player then agree by construction, and `parity_test` enforces it.
- **Fixed 60 Hz, interpolation on for the player only.** The jump does not depend on the display's refresh rate. The camera and anything moved in `_process` are not interpolated, or they would glide from their last position.
- **Doors keep momentum and place** (a body crossing keeps its height or column and its speed, and is pushed in about 20 px); a ceiling door gives a minimum upward speed so a slow player does not stall in the doorway.
- **Death goes back to the last safe floor, not a save point,** with a history of eight stretches so a bad spot costs one extra death and never a loop. An Imprint is never safe floor, because it breaks.

**Tokens, the 3TM, exit rules (PR #16)**
- **Imprint is earned: three tokens at a 3TM.** Tokens are the currency, a 3TM the shop, one upgrade per machine. Partial deposits are saved; a spent machine does nothing; the pocket holds three.
- **A room's exit rule blocks every door, including the one the player came in by,** with solid shaded blocks, not glows. `exits: pickups` is the first rule. A rule is a flag test, so a reload gives the same answer.
- **The body is the inventory.** Tokens and the Imprint line are cut into the player's square, so no HUD is needed.

**Save rooms and health (PR #26)**
- **Dying with no health goes to the save room.** Health is a count of pips, none at the start. With a pip, a death spends it and keeps the old safe-floor respawn. A pip is a pickup that is designed and not built, so today every death goes to the save room.
- **A save room is named `s<n>`, and has exactly one save machine.** The id says what the room is, so a numbered room can never be one and a save room cannot be without its machine.
- **Entering a save room makes it the save room.** Before the first, a death goes to the start room's `P`. Only the latest counts.
- **A reload resumes at the save, and nothing is undone.** The file keeps every pickup, token and 3TM fill, and only the place is the save. The user chose this over rolling the world back to the moment of saving.
- **Room 1 became `s1`, and its doors wait for its machine (`exits: saved`),** the same way room 2's wait for its token. Saving is the first thing the player does, which is why a death with no health brings them back there. The machine is on the middle platform, so the player passes it on the way up.
- **The machine holds the player for a second and lights up,** so saving is something they see. A player put on a used machine by a respawn or a reload is not held again.
- **The save is version 3,** and a version 2 file carries over (room 1 renamed, its machine counted as used, `s1` as the save room), because the player's own game was a version 2 file.

**The save machine becomes a split sphere (PR #27)**
- **It is a sphere that takes the player in, spins, and pops them out on the other side,** from the user's drawing: an open sphere with an invisible zone around it, the player hopping into the middle, it closing and saving, then opening and popping them out. It first took about a second, as the ring did. The spin was then made 1.5 times longer at the user's request, so a save takes 1.2 s.
- **It is shaded with close horizontal lines all across it.** The user asked for some shading or lines that are clearly different from the doors' halos, which are dithered dots with rings. Lines of latitude that crowded towards the bottom were tried first, and the user asked for close lines all across instead. They stay level when the halves open, since at two pixels apart a tilted line breaks into a checkerboard, which would look dithered.
- **It works once each time the room is entered.** Stepping off and on used to save again and take control again, which stopped the player over and over and left them unsure whether they had saved. The machine now stays closed after use, so it looks done, and a new visit builds it open.
- **A save room holds only its machine, and platforms.** The user's plan is for a save room to be a place to save and nothing else, and the loader enforces it.
- **The zone is 5 x 3 cells and the floor under all of it is solid,** so the player is popped out onto either side and never into air.
- **A respawn or a reload puts the player inside the shut sphere, and it pops them out to the right** with no second save. The user chose this over standing them beside it. It first sat shut for 0.1 s before opening; the user then asked for the same spin as a save, so coming back looks like being saved and let out.
- **It stays closed after use** (the user chose this over a filled-in open look).
- **The save file has not changed.**

**The world map and one-way rooms (PR #17)**
- **`trap: allowed`** marks a room that is a dead end on purpose (rooms 7, 8 and s2, until room 7's way out is built). It turns "no way home" into a warning in that room and relaxes nothing else.
- **The solver follows a fall of any height** (`FALL_LIMIT`), because room 7 is four screens tall.
- **Room 7 is one screen wide.** The screen to its right was empty. The fall stays four screens tall, and the ceiling door stays lined up with room 6.
- **Room 3's entrance lines up with room 2 but cannot reach the token,** and `door_test` checks the level crossing while `reach_test` checks that the staircase is still required, so a later edit cannot restore the old drop or quietly make the climb optional.

**Imprint's look and timing (PRs #18 and #21)**
- **The cursor is always a dotted outline,** whether or not the platform can be reached. A filled cursor with a circling sparkle (and a trailing dotted tail) was built and removed at the user's request. The reach check still runs, so a look that tells them apart can return.
- **A placed platform is drawn over the cursor,** so what can be landed on is never hidden.
- **The dashes are a clock:** four, one going in each equal share of the life, from the left; the last dash blinks (the blink lasts the last dash's share, so it scales with duration and width).
- **A platform lasts 2.5 s** (it was 4, then 3). It was tuned by playing. Saves from before the change keep their old value.

**The map and saving (PR #20)**
- **Three zoom levels,** Out always showing every visited room, however big the world gets. In is twice Middle, on the player. Redrawn at each scale and not stretched, so lines stay one pixel.
- **The zoom is part of the saved game, and a new game resets it** (the user's choice over a separate preferences file). Closing the map after a change saves.
- **`?new-game=1` deletes the save at startup.** Before, it only ignored the save until the first autosave, so a reload in between brought the old game back. A plain reload keeps the save.
- **The map layer is moved, not viewed through a `Camera2D`.** The camera lagged one zoom step behind the marker because it only moves in the physics step.
- **W and S zoom like Up and Down.** The game is paused with the map open, so jump (W, Up) is not triggered by pressing them there.

**The solver (PR #22 and before)**
- **Sample, do not search everything.** Fixed input plans per ledge. An unreached ledge is a warning, an unreached room, door or pickup an error.
- **Imprint is searched from ledges only, one platform at a time,** from the arcs a jump actually makes, then verified with the platform in place. Mid-air placement and two in a row are left out, and the docs say so.
- **A room's "needs" is found by dropping pickups one at a time.** It is the answer to "what must the player have first", and is printed by `validate.sh`.
- **The validator's time was the Imprint search, not repeated solves** (measured: about 12 of 16 s was the legs off each candidate platform). So the fix is a cache of what depends only on a room and the solver, in `build/solver-cache/`, keyed by two fingerprints.
- **Threads were tried and dropped.** GDScript's simulation only runs about 1.5 times faster on two or four threads and slower on eight; the whole validator went from 15.6 s to 13.2 s. Not worth the risk. A collision step with no dictionary was worth about 7% and was not kept.
- **The tests never read the cache,** so they always check the solver itself.

**Moving platforms (PR #29)**
- **A moving platform is drawn with its track,** as a row of its legend glyph and `-` or `|` out to where it turns (the user's choice over writing the path as numbers in the legend), so the file shows its path the way the rest of the room shows its shape.
- **It moves at a set speed,** `speed=` in pixels a second, and waits at each end, `pause=` (0.2 s, "a split second"). The user first asked for 1.5 s from end to end, then for 60 px/s and then 75 px/s, to try in playtesting. Room 8's is 5 cells wide, the user's choice over 2 or 3.
- **Leaving it keeps only the player's own velocity.** That was the user's choice for the first version. Without carry-over, a jump from a moving platform never lands back on it if the platform is faster than the player can run (90 px/s). The user had carry-over switched on to playtest it, then off again, so `inherit_platform_velocity` is off in `movement.tres` and the switch stays for trying it again.
- **It is not drawn with a track in the game,** at the user's choice. The renders draw the track.
- **Its clock starts when its room is built,** at the drawn end, waiting, and nothing about it is saved, so it is always in the same place on entering.
- **The row above wherever it goes is kept clear,** and so is a cell around every door. That keeps riding from ever scraping, crushing or killing the player, or carrying them through a door. It is also what lets the solver say that a player on a platform can wait for any moment of its trip.
- **It is never safe floor, and pushing someone into a wall crushes them,** like a death on spikes.
- **The player and the solver share it.** `MovementSim.step` carries and pushes, the solver tries moments spread over its trip, and `platform_test` checks the real player and `simulate_jump` end in the same place with a platform moving.

**Dev tools (2026-10-24)**
- **Testing is isolated.** The user chose returning to their normal save over permanently granting cheats. F4 now shares that protection.
- **F2 and an explicit export opt-in.** F2/DEV opens the panel; `?dev=1` / `--dev` enables exported tools, including the release browser build.
- **Fresh direct launches and reusable named loadouts.** Direct launches reset progression. Loadouts remember only powers and resources, usable in any room.
- **Retry the original test, with the latest explicit tuning.** Cross-room attempts reset progression to their baseline, while duration/width/resource edits remain selected. This avoids replaying the game and avoids silently saving depleted resources as the next loadout.
- **Door bypass and automatic death retry are optional, initially off.** They are separate from real room requirements and ordinary health behavior.
- **Future mechanics must include their dev path.** Registration, setup/removal, retries, loadouts, tests and docs are part of completion, enforced by agent guidance and coverage tests.

**Process**
- **One record.** `AGENTS.md` for how an agent works, `README.md` for the code and its rules, this file for the game and its decisions, `docs/testing-checklist.md` for what nobody has played. `docs/plans/` is history.
- **Every new test is mutation-checked,** and the pull request says which mutants were tried.
- **A pull request is one piece of work, called by its number,** opened on a branch, with the docs in the same change. Merged only when the user says so.

### Guardrails for a change

Do not: copy a movement formula; reference an autoload from a pure class; derive or rename an entity id; change the save's shape without `Save.VERSION` and a `_migrate` step; put a `Camera2D` back in the map; add threads to the solver; make the cursor or any effect fade (nothing fades: a pixel is on or off); add colours (the picture is two colours); call a tuned number the default without saying so in the docs; or leave a test you have not tried to break.

## Not decided

- What S / Down does.
- How hard a bounce platform throws the player, and whether the player aims it.
- A gamepad or keyboard way to aim and place an Imprint.
- How many tokens an upgrade after Imprint should cost, and whether the pocket should ever hold more than three.
- What a spent 3TM should offer, if anything.
- Whether `~` cells should ever be drawn.
- Sound, throughout.
- The title card for room 7, and what its 3TM is for.
- Whether a save from before a change to a starting number (Imprint's duration went from 4 to 2.5 s) should be brought up to date. Today it keeps the old number, because the save stores the abilities.
- A way to start over from inside the game. `--new-game` does it from the command line and the web address.
- How a health pip is found, how it shows on the body or the screen, how many a player can hold, and whether a save room refills them.
- Whether a death with health should cost anything besides the pip.
- Whether leaving a moving platform should keep its speed (`inherit_platform_velocity`, off now; tried on and turned off again), and room 8's platform's speed (75 px/s), pause and height (row 13, four cells up). All are to be tried in playtesting.
