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
| Imprint upgrades beyond the numbers (longer, more at once, bounce) | Designed, not built |
| The solver using Imprint, and what each room needs | Built |
| The solver's cache between runs (a repeat validate takes about 2 s) | Built |
| The map's three zoom levels, its legend, saved with the game | Built |
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

The header holds `exits:`, `legend:` and `trap:` in any order. `trap: allowed` is described under Checking rooms; it is for a room that is a dead end on purpose.

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

- Touching it with no tokens shows how full it is ("2 of 3 tokens").
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

The game saves to `user://save.json` when a room is entered, when a pickup is taken, and when the map is closed after its zoom changed, and loads it on start. The file holds a version number, the room and the position in it, the visited rooms, the abilities, the map's zoom level, the number of tokens carried, how full each 3TM is, and the flags (one per pickup taken, `pickup:<id>`, and one per token taken, `token:<id>`). On entering a room the position is where the player arrived. After a pickup it is the last safe floor in that room, so loading never puts the player in the air above spikes.

A file that cannot be read, or that a newer version of the game wrote, is moved aside as `save.json.bad` and the game starts new, so it is never overwritten. A save for a room that no longer exists keeps the abilities and the map and starts in the start room. Headless runs and games started with `--room=` or `?room=` never read or write a save. F4 only warps inside a normal game, which keeps saving. `--new-game` (`?new-game=1`) is the only way to start over: it deletes the save and empties the game's state before anything is placed, so even a reload before the first autosave cannot bring the old game back, and the map's zoom goes back to the middle. A plain reload keeps the save. While `?new-game=1` stays in the address, every reload is a new game. A save from before tokens existed (version 1) is also set aside, because it comes from a world where Imprint was free and its flags mean something else now. To change the save's shape, raise `Save.VERSION` and add a step to `Save._migrate`; to give up on older files, raise `Save.OLDEST`.

### The current slice

Seven rooms, as content, not as the limit of the format. The flow they make: take the token in room 2 to leave it, take one more in room 3 and one in room 5, spend all three at the 3TM in room 4 to get Imprint, use Imprint to cross the spikes in room 5 and then the wall in room 6, and fall into room 7.

```
 1   2   3          room 2's floor door drops into 5, room 3's floor hole into 4
     5   4          5 and 4 meet at their side doors, 5 and 6 at theirs
 6                  room 6's floor door drops into 7
 7
 7
 7
 7
```

- **1**, one screen at `(0, 0)`. Three tiers of platforms, each a running jump apart, and an exit in the right wall. This is the movement test.
- **2**, one screen at `(1, 0)`. The landing from 1's door, steps down to the right, a hole in the floor (cols 23 to 27) that drops down to room 5, and a door high in the right wall at the end of a ledge (row 9, cols 25 to 30), reached by a jump from the lower platform. It has `exits: pickups` and a token on the first platform, so it cannot be left, by any of its three doors, until the token is taken.
- **3**, one screen at `(2, 0)`. Its two-cell door and entrance ledge line up with room 2 (door rows 7 to 8, ledge row 9, cols 1 to 8), so crossing between them stays level. A hole in the floor (cols 5 to 10, mostly under the ledge) drops down to room 4. A staircase climbs from the first step (row 14, cols 13 to 17) to platforms on row 10 (cols 22 to 27) and row 6 (cols 26 to 29), then back left to the token platform (row 5, cols 18 to 21). The upper platforms are too far right for a jump from the entrance ledge, so the player still has to descend and climb the staircase. Its first step also climbs back onto the ledge, for the way back to room 2.
- **4**, one screen at `(2, 1)`, under that hole. Three platforms step down from under the ceiling door, each 4 cells apart, so the door is a short climb in and a short climb out. The 3TM stands at the bottom left, beside the left door that leads to room 5.
- **5**, one screen at `(1, 1)`, with doors in the ceiling (up to room 2), the right wall (to room 4) and the left wall (to room 6). A pit of spikes 16 cells wide, with a short floor on its left, is too wide to jump. Three platforms climb from the right-hand floor back up to the ceiling door, and a token sits on the middle one. A player standing on the middle platform can cross the pit by putting an Imprint platform in the gap, and can cross back the same way. It is the first room that is open or shut by an ability.
- **6**, one screen at `(0, 1)`, through the door in the right wall of room 5. A hole in the floor is covered on the player's side by a roof and a wall six cells tall, taller than a jump, so a platform put down by the wall is the only way up onto the roof, and from there the player walks off the end into the hole.
- **7**, one screen wide and four tall at `(0, 2)`, under room 6's hole. It is empty: a long fall onto a floor. It is marked `trap: allowed`, because nothing in it leads back up yet. A 3TM and a title card that fades in during the fall and out before the landing are planned.

### Starting in a room

For testing, the game can begin in any room: `--room=<id>` on the command line, `?room=<id>` on the web, or F4 in a debug build while playing. The player is put on that room's `P`, or just inside its first door if it has none. An unknown id is reported and the start room is used.

### Checking rooms

A room is not finished when it loads. `tools/validate.sh` also plays the whole world with the movement simulator, starting from the `P` in the start room, and fails if the world cannot be played.

A **ledge** is a run of cells with air above and floor below. From each ledge the solver tries walking off either end, and jumps from every cell with the input held left, none, or right, and the jump held for a tap, a hop, or the full leap. Each try is the same `MovementSim` the player runs. A try that lands on another ledge, or touches a door, is an edge in the graph. A try that touches a door records the body's position and velocity there. `Door.crossing`, the same function the game uses, says where that body appears on the far side, and the solver lets it fall or walk from there to see which ledge it lands on. A body that touches spikes is dead, so a path through them is not a path. A body that falls through a door keeps falling to the bottom of the room it lands in, however tall: room 7 is four screens high.

- **Error:** a room, or a door in a reachable room, that no path from the start reaches.
- **Error:** a door that every body going through it lands on nothing after, because the room beyond has a void or only spikes under it. The check is that some entry lands on a ledge. It does not promise that every entry does, so a shaft can still be hard to climb out of: play it.
- **Error:** a trap, meaning a ledge the player can reach but from which no path leads back to the start. Falling into a pit too deep to jump out of is one. The first version of room 3 was one.
- **Error:** a pickup, token or 3TM in a reachable room that no sampled path touches. A path that touches it and then dies on spikes still counts, because the pickup was taken. Only paths that start on a ledge are tried, so a pickup that can be taken only by falling through a door onto it is reported as out of reach.
- **Error:** a room whose exit rule is never met. Its doors never work, so everything past it is out of reach and its own floor is a trap.
- **Warning:** a ledge in a room that says `trap: allowed` with no way home, and the door that nobody inside such a room can touch. A room can say it in its header when it is meant to be a one-way drop (room 7, until its way out is built). It still has to be reachable from the start, and nothing else about it is relaxed.
- **Warning:** a ledge nobody reached. The solver tries a fixed set of inputs, so a ledge it misses might still be reachable by a path it did not think of. Look at the render and decide.

`tools/render.sh` draws each room and the world map to `build/renders/`. Red bars mark unreachable ledges, yellow bars mark traps, and orange marks a door that was sealed.

**Imprint in the solver.** The solver takes the player's `Abilities`. With Imprint unlocked, a ledge gets extra edges: a player standing there can put a platform down, jump onto it, and jump from it.
- It does not try every platform. From each ledge the usual jumps are simulated once, and a platform is a candidate only where one of those jumps comes down through the top of a cell row, and only if it is a legal place (the same `ImprintRules` the cursor uses) within a jump of something still out of reach. Each candidate is then checked by simulating the jump again with the platform in place. A platform that passes is searched from like a ledge of its own.
- A platform lives `imprint_duration` seconds, so each of the two jumps is cut to half of that less a little spare time. A one second platform crosses nothing.
- A ledge that cannot get home is searched the same way, with the ledges that can as the targets, so crossing a pit one way with a platform and having no way back is still a trap.
- Left out: putting the platform down in mid-air, and using two in a row. A room that needs either is reported as out of reach even if a player could do it. A room that needs the platform in a place the reach check calls out of reach is also not found.

**What a room needs.** `tools/validate.sh` solves with the starting abilities, takes every pickup that solve could reach, solves again with what they gave, and repeats to a fixpoint, when nothing new turns up or the newly reached things do not change the abilities. The number of things in the world makes this finite; if the search ever fails to settle within that bound, validation fails instead of accepting a partial answer. A room, a ledge, or a pickup that only opens in a later round lists the pickups it needs, cut down by dropping them one at a time to a set it still opens with. Example, from the current world: `Room 5: the ledge on row 16, cells 0-4 needs r2_token, r3_token, r4_3tm, r5_token`. Errors come from the last solve, so a room that stays shut even with every pickup is an error. Tokens and 3TMs are part of this. A token reached is taken. A 3TM reached gives its upgrade if three tokens are taken for it, and several machines are paid in the order of their ids. A room with an exit rule keeps its doors shut in the search until what the rule asks for has been reached, so a room is only open if the player can first do what it asks. The search does not model the carry limit of three (a player who cannot take a fourth token before spending three is not caught), and it does not treat a blocked doorway as a wall for a body falling through a chain of doors. A trap is judged where the player could first be in it, with the fewest abilities, because a player who has not found Imprint yet is also stuck in a place that needs it to leave.

**Speed, and the cache.** A cold run is about 16 s for 7 rooms, and nearly all of it is the Imprint search: each ledge's jumps (about 1 s) and, for every platform Imprint could put down, a "leg" of about 40 simulated jumps from it (about 12 s). What the solver works out about a room depends on nothing but the room and the solver, so it is kept between runs in `build/solver-cache/<room>.json`: the jumps from each ledge, and each platform's leg by cell, width and length. A room's file is used only if two fingerprints match: the room's (its grid with the openings that lead nowhere sealed, its doors and where they lead, its things, where it sits, so a neighbour that appears or moves counts) and the solver's (a hash of the code and numbers that decide a jump: `reach_graph.gd`, `imprint_search.gd`, `movement_sim.gd`, `movement.tres`, and the others listed in `SolverCache.SOLVER_FILES`). Change either and that room, or every room, is worked out again. What is not kept is cheap and depends on more than one room: where a door leads, and the search that spreads out from the start. A warm run takes about 2 s however many rooms are unchanged, and a run after editing one room redoes that room's share. A file that cannot be read is ignored. The tests never read the cache. `tools/validate.sh --no-cache` ignores it too, and prints the same answers.

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

Status: built: finding it (three tokens at a 3TM), placing it, the reach check, the lifetime and its countdown, and the rules below. The solver knows about it, so `tools/validate.sh` proves which rooms are open or shut by it. Widening, lengthening, more at once and bounce are stored as numbers (width and duration are read when a platform is placed) and no room gives them yet.

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

Ideas for later upgrades, none of them built:

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

1. **Per room** (`parse_room`): split the header from the grid at a line of `---` (a header with no divider is an error); read the header (`legend:` lines, `exits:`, `trap:`, each given at most once, every bad line an error with its line number); read the rows (every row the same width, the room a whole number of 32×18 screens); work out `screens`, `pixel_size` and `bounds_cells` (the whole room, not one screen, since an Imprint may go anywhere in it); scan the cells once (the spawn, `~` cells, spikes, glyphs that mean nothing, outer-wall cells that are not `#` or `X`, and where each legend glyph is drawn); check each 3TM's 3×3 cells are open air; check the exit rule makes sense for the room.
2. **Across rooms:** two rooms may not occupy the same screen cell; an entity id may be used in only one room.
3. **Doors** (`_parse_exits`, `_link_exits`): runs of `X` on one edge become doors, split where they cross a screen boundary; an `X` on a corner or off the edge is an error. A door's destination is the room on the neighbouring screen cell. It pairs with exactly one opening on the opposite edge whose span overlaps it (any other count is an error and the door is cleared).
4. **Sealing:** an opening with no room beyond it becomes solid (`_seal_dead_ends`), so `RoomInfo.rows` is the room as played, and room fingerprints see it.
5. **Solids:** `merge_solids` joins runs of `#` into rectangles (a run is merged with the run directly under it when both have the same start and length). The player and the solver collide with these rectangles, never with cells, so there are no seams to snag on.
6. **Start room** must exist and have a `P`.

Errors are sentences naming the room (and the line, for the header). A bad drawing tends to repeat one mistake along a wall, so each kind is capped at `MAX_PER_KIND` (5) per room and the rest counted.

### The movement (`player/movement_sim.gd`, `player/movement_config.gd`)

`MovementSim.State` holds a body's position, velocity, `grounded`, `coyote`, `buffer`, `launched`, `cut`, and, after a step, `jumped` and the `floor_rect` it stands on. `step(cfg, state, rects, input_x, jump_pressed, jump_held, delta)` does one tick, in this order:

1. `integrate`: horizontal speed moves toward `input × run_speed` at the ground or air acceleration (or friction when there is no input); the coyote timer is set while grounded and counts down; the jump buffer is set on a press and counts down; if both are above zero a jump starts (`vy = -jump_speed`); otherwise a released jump that is still rising is cut (`vy × jump_cut`, once), and gravity is applied, scaled by `apex_gravity_scale` while `|vy| < apex_threshold` and by `fall_gravity_scale` while falling, capped at `max_fall_speed`.
2. `corner_correct`: a body moving sideways into a block and not rising is lifted up to `corner_correction` px if that clears it; a rising body that clips a ceiling corner is pushed sideways by up to the same. Both look ahead with a blocked test and never move through a block.
3. `resolve`: move on x, push out of any block it overlaps; move on y, push out, and `grounded` is set when it came down on a block.

The body is `HALF` = 5 px either side (a 10×10 box). `standing(position, rects)` is a probe one pixel down. `simulate_jump(...)` repeats `step` at a fixed 1/60 s from a start position and velocity until the body lands (grounded after leaving the ground, past tick 2), touches a trigger rect (a door), touches a hazard rect (it died), leaves `bounds`, or runs `limit` ticks (180 by default). It returns the final position and velocity, `landed`, the floor rect, `trigger` (the index touched or -1), `hazard`, the `collected` indices among rects passed as `collect`, the tick count, and, with `record`, the whole path. `later_input` and `switch_frame` change the steering part way through. Everything that needs to ask "what would the player do" calls this. The player's own node calls `step` with the real input and `delta`.

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

After any take, `recheck_exits` runs and the game autosaves.

### Dying and safe floor (`world/world.gd`, `world/room.gd`)

Touching spikes, or leaving the room's outline by 60 px, calls `_die`: the world goes busy, platforms are cleared with shards, the player shatters, and after `DEATH_TIME` (0.6 s, on physics time) `_respawn` puts them on the last safe spot. The world keeps `SAFE_HISTORY` (8) stretches of floor. Each entry is a room and a position, and a new position within `SAFE_SPACING` (30 px) of the stretch's start updates that entry instead of adding one. A spot is recorded when the player stands on the room's own floor (not an Imprint, not a door block) with no spikes within a cell to either side and no door within two cells (`Room.is_safe_spot`). If the player dies again before standing anywhere new after a respawn, that spot was no good and the newest entry is dropped first.

### Saving (`autoload/game_state.gd`, `autoload/save.gd`)

`GameState` holds what a save holds: `visited` (a set of room ids), `abilities`, `flags` (`pickup:<id>`, `token:<id>`), `tokens` carried, `machines` (id → tokens inside), `map_zoom`. `to_dict` and `load_dict` are the only two places that know the shape, and `load_dict` clamps and defaults everything, so a damaged file gives a smaller state and not a crash. `Save.write(room, position)` adds `version`, `room` and `position` (room pixels) and writes `user://save.json`. `Save.load_game()` returns where to put the player, or `{}`. `VERSION` is 2 and `OLDEST` is 2: a file older than `OLDEST`, newer than `VERSION`, or not valid JSON is renamed `save.json.bad` and the game starts new. `Save.enabled` is off in headless runs and for `--room=` starts, and `write`, `load_game` and `erase` all do nothing while it is off. A save written before a field existed loads with that field at its starting value, which is why changing a starting number (Imprint's duration) does not reach old saves.

Writes happen on entering a room (the arrival position), after a pickup, token or 3TM (the last safe floor in the room, so a load never puts the player in the air over spikes), and when the map is closed after the zoom changed (`World.save_now`).

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
- **Edges.** For every ledge, `_ensure_edges` simulates: a jump from the left end, every cell centre and the right end (`start_xs`), with input left, none or right (running only if there are `RUN_UP` = 5 px of ground behind it), and the jump held `HOLDS` = 3, 8 or 90 ticks; and walking off either end. `try_plan` simulates for `limit` ticks (`frame_limit`, 180) against the nearby solids (`near_solids`: ±`REACH_X` 170, up `REACH_UP` 100, down `REACH_DOWN` 400). A path that lands on another ledge is an edge; one that touches a door records a `Touch` (door, position, velocity; two touches within 10 px and 45 px/s are one); one that touches a pickup, token or 3TM records it, even if it then dies on spikes; one that touches spikes is dead and counts for nothing else. A ledge that runs into a door's trigger walks into it.
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

`ExitHalo` is a dithered half-disc of 12 pre-painted 64 px frames, played as a pulse. `Shatter` is 14 square shards that fly out and fall for 0.5 s; nothing fades. `Toast` (layer 15) shows a line for 2.5 s. `FlyingToken` arcs 16 px high with a trail of 6 recent positions, every other one drawn. `InventoryMarks` cuts black plus-shaped 3×3 marks out of the body at (4,2), (2,4) and (6,4) for tokens one to three, and a line on row 8 from column 1 to 8 once Imprint is unlocked. `DebugOverlay` (layer 20) shows F3's readout, and in a debug build the load errors and the F4 warp.

### What the solver and the preview do not model

- Placing a platform in mid-air, and using two in a row. A room that needs either is reported out of reach.
- The carry limit of three tokens, and a blocked doorway as a wall for a body falling through a chain of doors.
- Paths other than the fixed plans (the inputs and holds above), so "unreachable" can mean "a plan it did not try". That is why an unreached ledge is a warning and an unreached room, door or pickup is an error.
- A ledge's `MAX_CANDIDATES` cap, and `REACH_*` windows: a platform beyond them is not tried.

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

**The world map and one-way rooms (PR #17)**
- **`trap: allowed`** marks a room that is a dead end on purpose (room 7, until its way out is built). It turns "no way home" into a warning in that room and relaxes nothing else.
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
- Where the player resumes: a dedicated save point glyph, if autosave on room entry feels wrong.
