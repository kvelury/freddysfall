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
| Tokens, carried and shown in the HUD's heart, and the 3TM | Built |
| Double jump, the first power-up (room 4's 3TM) | Built, and the solver uses it; not yet tuned beyond the user's first play |
| The gun (room 9's 3TM) and breakable walls (the box round room 7's pip) | Built, and the solver uses them (the pip needs room 9's 3TM) |
| A `prize=health` 3TM | Built; no room uses it now |
| Save rooms, the save machine, `exits: saved`, and the health count that death uses | Built |
| Health pips: the pickup (one in room 7), the HUD's bar, and a save room refilling them | Built; not yet played by a person. A cap is not decided |
| Imprint width, duration and multiple active platforms | Built; available in dev tools, not awarded by current rooms |
| Imprint lockout (no replacing), 1.5 s duration, and a cooldown that is off by default | Built; the cooldown is tried through dev tools, no room awards it |
| Shrinking Imprint, default width 2 (3 only in dev tools; no room awards it now) and the Classic dev switch | Built; not yet played by a person |
| Imprint bounce and other special behaviors | Designed, not built |
| Aiming Imprint without a mouse: fixed slots, dash-style and build mode, controller | Planned, not built; a concept video was recorded (see "Aiming without a mouse") |
| Isolated dev tools, named loadouts, retries and door bypass | Built |
| The solver using Imprint, and what each room needs | Built |
| The solver's cache between runs (a repeat validate takes about half as long as a cold one; see "Speed, and the cache") | Built |
| The map's three zoom levels, its legend, saved with the game | Built |
| Moving platforms: drawn with their track, ridden, and checked by the solver | Built |
| The main menu (Start Game, or Continue and New Game, and Controls), the pause menu (Esc or P), the Controls page, power popups, and title cards (room 7's "Freddy's Fall") | Built; not yet played by a person |
| Softer two-color palettes | Designed, not built |
| Rendered at 640×360, two screen pixels to a world pixel, the world drawn exactly as at 320×180 and the text sharper | Built; not yet played by a person |

## What it is

Freddy's Fall is a sidescrolling metroidvania adventure. The player moves through a network of rooms. An ability they do not have yet is what opens the next path.

The first power-up is double jump. Imprint, where the mouse cursor becomes a platform, is built but for now is handed out only by the dev panel (F2). Until powers exist, the rooms are a movement toy with a map. After it exists, room layout is the lock and the platform is the key.

## Philosophy

**Movement is a specific feel, taken from one place.** The jump comes from the variable-jump, apex hang, fast fall, jump buffer, coyote time, rounded-ledge correction, and momentum described in section 4 of the Hollow Knight notes. That section is the whole of the borrowing. Combat, charms, art, map style, and anything else from that source are not part of this game.

**The picture stays small on purpose.** Geometry is solid pixel blocks. The player is Freddy the frog, a picture the size of one cell. Effects are few and they mean something: dust when you land, a halo on an exit, a shatter when a platform breaks. The world is drawn one bit, black and white, so a block, a gap, and the player read instantly; Freddy alone is in colour (see "The player's picture") at 320×180 world pixels. The screen is drawn at twice that resolution so text is sharp, but the world is still drawn in those blocks (see "Frame and scale").

**Two colors, gentler in the dark.** Pure black and white is the authoring language and the default look. It is harsh for playing in a dark room. The softer version is still exactly two colors, remapped at the end of the frame. The world does not gain a third color. The one exception is Freddy, who the user chose to colour lime (2026-10-28); how the palette pass treats him is under Not decided.

**Everything shares one grid.** The player, authored platforms, exits, and Imprint sit on the same 10 px cells. A jump you can see is a jump the movement numbers can make. Rooms are tested against the same simulator the player runs.

**A room is a place. The screen is a window.** A room may be one screen, or several screens side by side or stacked. Inside a room the view moves continuously with the player. Crossing into another room is a distinct act: a door, a slide of the frame, a new place on the map.

**The map and the level are the same doors.** An exit is an opening in the room's outer wall. The map draws that opening. Doors are inferred from which openings face each other, so the map cannot claim a connection the level does not have.

**It has to run in a browser, on a modest machine.** Godot 4, GDScript, the Compatibility renderer, and a web export with threads off, so a static server is enough and Safari does not need special headers. Physics is a fixed 60 Hz. The display may be 60, 120, or 144 Hz. The jump does not change with the refresh rate.

## Frame and scale

| | |
| --- | --- |
| Cell | 10×10 world px. The player is one cell, a 10×10 box. |
| Screen | 32×18 cells, 320×180 world px. This is the part of the world the camera shows, not the room. |
| Render | The viewport is 640×360: `Display.RENDER_SCALE` (2) screen pixels to a world pixel. The camera is zoomed by that, and text and other UI are drawn at the finer resolution. |
| Window | Integer nearest-neighbor scale of the viewport, aspect kept. Default window 1280×720, which is 2×. |
| Physics | 60 ticks per second. 2D physics interpolation on. At most 8 steps per frame. |
| Display | `max_fps` 0, vsync on. Movement math uses `delta`, so the tick rate can change later without rewriting the feel. |
| Filter | Nearest. Pixels stay pixels. |
| Font | One font for all text: Pixel Operator 8 (CC0, `assets/fonts/`), set in `UiTheme.FONT` and as the project's default font. It is imported with no antialiasing, hinting or subpixel positioning, and drawn at sizes that are whole multiples of 8 (body 8, titles 24), so a font pixel is a world pixel. Titles use its bold cut, `UiTheme.TITLE_FONT`, in capitals: change that one constant to give titles their own font. Text that is drawn by hand (key caps, map room ids) uses `UiTheme.FONT` too. |

The camera follows the player’s interpolated display position each rendered frame and snaps to whole world pixels. The player stays interpolated. A camera sitting between world pixels shimmers when the view is scaled up by a whole number.

**The world-pixel grid.** Everything in the world is drawn on whole world pixels, so at 640×360 it is the same picture as at 320×180: each world pixel is a 2×2 block of screen pixels and nothing is finer. Positions and rect corners are whole world pixels (`Display.snap`, `Display.snap_rect`), and shapes that were polygons are pixel pictures (`PixelShapes`, drawn by `PixelArt`). Only UI is finer: text is drawn at the screen's resolution. A thing that is meant to be finer than a world pixel, by decision, joins the `Display.FINE_GROUP` node group so the pixel check leaves it out. Nothing is in it yet.

## Controls

| Action | Keys |
| --- | --- |
| Move | A / D, or Left / Right |
| Jump | W or Up. Once double jump is found, press it again in the air for one more jump. Space is the gun's key and no longer jumps. |
| Shoot | Space, once the gun has been found. One shot a press, in the way the player faces. |
| Down | S or Down. Reserved. No action is assigned. |
| Imprint | Left mouse button, once Imprint is unlocked (for now only through the dev panel). Mouse only. |
| Map | Hold Tab, or hold M. M exists because a browser may steal Tab for focus. While it is held, Up or W zooms in and Down or S zooms out. |
| Pause | Esc or P. Opens the pause menu (Resume, Controls, Main menu), and closes it. |
| Palettes | Not assigned. P pauses now, so the palette key is to be chosen when that is built. |
| Frame rate | F3. Shows FPS and frame time. A development readout, not a player feature. |
| Dev tools | F2, or Dev tools in the pause menu (no button on the play screen). Editor/debug builds, or exports opted in with `?dev=1` / `--dev`. |
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
| Air jump (double jump) | `air_jump_speed` 267 px/s, one per landing | A press in the air, once double jump is found, with no ground or coyote jump to use, jumps again at the ground jump's speed. Made at the top of a jump it rises as far again: about 102 px (about 10 cells) in all, as high as a jump off an Imprint platform put down at the top of the first. Letting go early cuts it like any jump. Landing (on a floor, a lift or an Imprint platform), spawning, respawning and warping refill it; crossing a door does not. A coyote press is a ground jump and keeps the air jump. With none left, a press buffers a ground jump as before. |
| Corner correction | 3 px | Feet clipping a ledge by 3 px or less get pushed up onto it. A head clipping a corner by 3 px or less while rising gets pushed sideways. Both use a movement test, not a teleport through the block. |

Freddy is drawn as a frog, 10 px wide and no taller than the 10×10 box that is the player (see "The player's picture" under Things in rooms), so none of what he looks like changes where he collides. His picture follows what he is doing: standing, one of eight walk pictures, a jump (legs thrown wide) for as long as he is off the ground, and a low, squashed picture for about an eighth of a second after landing. Landing kicks 2–3 dust pixels at the feet. Those pixels are not interpolated, so they appear at the feet and not halfway across the screen.

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
| `^` | Spikes. Not solid: the player can walk into them, and dies. Drawn as two teeth pointing away from the solid they sit against (`RoomInfo.spike_facing`): up from a floor, which wins, then left from a right wall, right from a left wall, down from a ceiling, and up in open air. The whole cell is deadly whichever way they point. |
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

**Dying.** Touching spikes, or leaving the room's outline by more than 60 px, shatters the player into a burst of pixels for about 0.6 s, and then, if they have health, empties one pip and puts them back on the last safe floor. With none left they go to their save room instead (see Health and save rooms). A moving platform that pushes the player into a wall crushes them, which is a death like spikes. A floor is safe if the player stood on it, it is the room's own floor, and it is not within a cell of spikes or within two cells of a doorway. A moving platform is never safe floor, because it will have moved. An Imprint is never safe floor either, because it breaks: standing on one over spikes and dying brings the player back on the real floor they stood on before, not in the air where the platform was. The safe floor can be in the room before: dying right after a door puts the player back through it. Spawning in a room also counts as a safe floor.

The last eight stretches of floor are remembered, for a death that has health to spend. If the player dies again before standing anywhere after a respawn, that respawn spot was no good and they go back one stretch, so a bad spot can cost one extra death and never a loop.

During the slide the camera is not following. It is on the tween. Afterward it follows again.

Solids are drawn in one chunk per screen, clipped to that screen, so a room several screens wide does not redraw geometry the camera cannot see. The player collides with every solid in the room, drawn or not, so it can land on a platform that is just off screen. Touching a door is a box overlap tested every tick.

### Health and save rooms

**Health** is a bar of pips with a length and a fill. The player starts with none. A pip is found as a **health pip** (kind `health`, no settings besides its `id`): a small plus sign that bobs. Touching it makes the bar one pip longer and fills that pip, sets the flag `health:<id>`, and saves, with no line of text (the HUD shows it); it is gone from then on, even once the pip is emptied. A `prize=health` 3TM does the same. There is no cap (see Not decided). **Entering a save room fills every pip again**, by a door, a warp, a reload or a death with no health; dying inside one and coming back on its floor is not entering it. The HUD shows the bar (see The HUD). Dying uses the fill:

- With one or more full pips, dying empties one and puts the player on the last safe floor, as above. The bar keeps its length.
- With none, dying sends them to their **save room**: onto that room's machine, a plain placement with the old safe floors forgotten, because they may be in rooms the player will not reach again. Nothing is undone. Pickups, tokens and 3TM fills taken since stay taken, and only the player's place changes.

A **save room** has an id of `s` and a number (`s1`, `s2`, …), a file `data/rooms/s<n>.txt`, and exactly one `save` thing in its legend, the save machine. It holds nothing else but platforms: no pickup, token, 3TM or spikes, so a player in a save room is never being asked to do two things. No other room may have a save machine. Entering a save room, by a door or by a warp, makes it the player's save room, and only the latest one counts, and fills every health pip. Before they have entered one, a death with no health goes to the start room's `P`.

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

The kinds are listed in `src/world/entities.gd`, with the settings each needs. There are seven: `pickup`, `token`, `health`, `machine`, `save`, `platform` and `breakable`. Adding a kind is a line there, a script in `src/world/entities/`, and a case in `Entities.create` (a platform is built by the room from its path instead; a breakable wall by the room from its cells). `Room.build` makes the things in a room and leaves out any that the player has already taken.

A **pickup** is a small diamond. Touching it gives its upgrade, shows one line at the top of the screen (a power with controls gets the power popup instead; any other upgrade reads its name and "+1", for example "Imprint Width +1"), and saves. It is gone from then on. What it gives is looked up in `data/upgrades.json`: each upgrade is a name, the ability it changes (`stat`), and a `kind`. A `max` upgrade raises a number and never lowers it, so finding a smaller one late does nothing. An `add` upgrade gains a named effect, once.

A **token** is a solid white diamond that bobs, where a pickup is hollow. Touching it puts it in the player's pocket, and it flies to the HUD's heart. The player carries at most three. Touching a token with three already carried leaves it where it is, with no message, and it can be taken once there is room. A token that has been taken stays gone, even after it has been spent. A token has no settings besides its `id`.

A **3TM** (3 token machine, kind `machine`, settings `upgrade=` and `value=` like a pickup, or `prize=health` for a health pip instead; exactly one of the two) is a square with a rectangle on top. The rectangle has three diamond-shaped openings. It fills 3 x 3 cells and the legend glyph marks the middle of its bottom row, so a 3TM standing on the floor has its glyph in the cell above the floor. Its 3 x 3 cells have to be open air, and it is not solid: the player walks in front of it.

- Touching it with no tokens does nothing; the openings show how full it is.
- Touching it with tokens takes them all, one at a time. Each leaves the player's body, flies in an arc with a trail to the next empty opening, and fills it with a flash and a burst of pixels. The player cannot move meanwhile. An Imprint platform does not age meanwhile either.
- Filled openings stay filled, and the count is saved, so a player can bring one token now and two later.
- When the third opening fills, the machine shakes and flashes three times and a spark flies from its mouth to the player. The upgrade is then given, with the usual line of text at the top of the screen.
- After that the machine is **spent**: its outline turns dotted, and touching it does nothing. A second upgrade needs a second machine.

A **save machine** (kind `save`, no settings besides its `id`) is described under Health and save rooms. Its 5 x 3 zone has to be open air and the five cells under it solid. A room with an id that is not `s` and a number cannot have one, and a save room has to have exactly one and nothing else but platforms.

The HUD shows the inventory (see The HUD). The player's body can show it too, but in normal play it does not: **the token marks are off**, and the **Imprint line is never shown** (below), so the body shows no inventory at all. A dev test can turn the token marks on ("Show token marks on Freddy", Dev playtesting); what follows is what they look like then. Each token carried cuts a small black line, two pixels wide and one tall, out of it. The first two stack on the side opposite the player's facing, from bottom to top, on rows 6 and 4 (counting from zero), with one pixel of body between them and the side edge and one clear row between them. The third sits in the middle of the body, columns 4–5, on row 5, level with the gap between the two, so no mark is up by the eyes. Facing right puts the stack in columns 1–2; facing left mirrors it into columns 7–8 (the third stays in 4–5). The pictures also carry an Imprint line, cut along row 7 from the middle to the front (columns 4–8 facing right, 1–5 facing left), one clear row under the third token, but it is not drawn (see the Decision log: it sat above the gap between his legs and read as a bite out of his belly); the diagrams below show it as a picture's data. No two marks touch, even at a corner. Each picture says where its own marks go (`FreddySprites.Frame.tokens` and `line`, in box pixels facing right), so a short picture keeps them. While he lands the picture is short: it shows up to two tokens, on rows 6 and 8 (the bottom one directly above the rear foot), and no Imprint line, for about 1/8 s. The marks are drawn on Freddy, below, and are only seen where he has body.

```
3 tokens       Imprint+3      Imprint only
.+++...+++     .+++...+++     .+++...+++
.+o+...+o+     .+o+...+o+     .+o+...+o+
##########     ##########     ##########
########..     ########..     ########..
#oo###yyyy     #oo###yyyy     ######yyyy
####ooyyyy     ####ooyyyy     ######yyyy
#oo###yyyy     #oo###yyyy     ######yyyy
######yyyy     ####oooooy     ####oooooy
.==....==.     .==....==.     .==....==.
===....===     ===....===     ===....===
```

`#` is his lime body, `y` the yellow patch on his front flank, `=` his legs (lime too), `+` white (the eyes), `o` black (the pupils, and the marks cut into him) and `.` nothing: Freddy standing and facing right, as `FreddySprites` draws him with the marks `InventoryMarks` gives.

Landing, the same three cases (up to two tokens, never the line):

```
3 tokens       Imprint+3      Imprint only
.+++...+++     .+++...+++     .+++...+++
.+o+...+o+     .+o+...+o+     .+o+...+o+
##########     ##########     ##########
#oo#####..     #oo#####..     ########..
######yyyy     ######yyyy     ######yyyy
#oo###yyyy     #oo###yyyy     ######yyyy
===....===     ===....===     ===....===
```

### The HUD

The user's drawing (a photo of a sketch, "Health/token UI"). A bar is fixed in the top-left corner at all times during play, and never moves with the camera. It is the one thing besides Freddy that is in colour: its outlines are red (`Hud.RED`, `#D22B2B`).

- **The heart** holds the tokens. It is three diamond slots, two lobes and a point, outlined in red as one shape, every slot's edge included. A slot is filled white for each token carried, left lobe, right lobe, then the point (the pocket holds three, so three slots). An empty slot is black.
- **The bar** holds the health pips. With none it is not there: the HUD is the heart alone. The first pip adds one square touching the heart's right tip; each one after makes the bar a square longer. A square is 7×7 inside, and neighbours share their 1-unit red border, so the whole bar is outlined red. A full pip is filled red, inset a unit inside its border so neighbouring full pips stay apart; an empty one (spent by a death) is black, so the bar shows what has been collected and what is left. After 30 pips it wraps under itself, so it never runs off the screen.
- **Nothing behind it.** Only the heart and the bar are drawn, with no plate. The heart's top-left is at (14, 14), clear of a room's one-cell outer wall.
- **Taking a token or a pip** sends it flying from where it was in the room to its slot, white with a red edge, speeding up as it goes (0.35 s). It counts in the HUD only when it lands: a token's slot flashes red, then fills white, and the heart jumps up a unit for a moment; a pip's square grows out of the bar's end a unit at a time (0.15 s), then flashes white and fills red. A `prize=health` 3TM's pip flies from the player.
- **Losing them.** A token spent at a 3TM empties its slot, from the last, with a blink (it still flies from the player's body to the machine). A death empties the rightmost full pip with a blink. A save room fills the empty pips left to right, a flash each.
- Nothing fades: every change is pixels switched on or off, on whole UI units. A load, a retry or a dev edit that rebuilds the world shows the state at once with nothing flying.

### The player's picture

The player is Freddy the frog (`src/player/freddy_sprites.gd`), drawn from the user's sprite sheets (`FREDDY THE FROG (OPTION 2)`). It is a picture of whole world pixels, 10 wide, inside the 10×10 box and standing on its bottom row. It is only a picture: the collision box, the movement, the jump and what the solver knows are unchanged. He is coloured as option 1 ("mono green") of the user's colour sheet: body and legs lime `#C6FB65` (sampled from the sheet), a yellow patch on his front flank (below), eye stalks white, pupils and the inventory marks black. `FreddySprites.COLOURS` (typed `Dictionary[String, Color]`) maps each row character to its colour; every pixel is one character, so layers never overlap and their order does not matter. The legs are their own character, `=`, lime like the body, because the user's colour sheet varied only the legs: any of its other options is a one-line change to `=`. Marks are cut only from body pixels (`BODY_PIXELS`: the lime `#` and the patch `y`) and become `MARK_PIXEL` (`o`), never from the eyes or legs. **The patch** is a yellow block, `y` in `FreddySprites.COLOURS` (`#F6EC00`), on columns 6–9 and rows 4–7 of the body facing right, so it is on his front and mirrors with him; it fills the lower of the two notch rows, leaving the notch on row 3 only. The landing picture has it on the same side, on its last two body rows. It is in every picture, since the body is shared. `problems()` rejects a character that is not in `COLOURS` or `EMPTY` (`.`), and a palette key that is not one character. Two eye stalks with a black pupil each stand on the head, the front is notched, and the rear is the side the inventory is cut into. Facing left mirrors the picture, once, after the marks are cut, so nothing else mirrors anything.

Each pose (`PlayerAnimator.Pose`: `STAND`, `WALK`, `JUMP`, `LAND`) has one animation, a row of a table (`FreddySprites.animation(pose)`): its pictures (`frames`, each a `Frame` with its rows, the box row it starts on and where its marks go), and how they play: `every`, a ground run in px (`by_distance`) or a time in seconds for each picture, and whether it loops. `PlayerAnimator` only says which pose and how long (`time_in_pose`) and how far (`distance_in_pose`, ground px) the body has been in it, both from 0 whenever the pose changes; the animation turns those into a picture with `index(time, distance)`. Which pose is shown, and how long a state lasts (`LAND_TIME`, `WALK_SPEED`), belong to the animator; how many pictures a pose has and how fast they go belong to the sprite set, so a second sprite set can reuse the animator. **To add an animation** (a hurt pose, say): a value in `PlayerAnimator.Pose`, one rule for it in `PlayerAnimator.advance`, and one row in `FreddySprites._build`. Nothing else changes; `FreddySprites.problems()` and `display_test` catch a pose with no row, an animation with no pictures, a picture that is not 10 wide or leaves the box.

| Picture | When | Rows |
| --- | --- | --- |
| Standing | on the ground, not moving | 10 |
| Walk, 8 pictures | on the ground, moving; one picture for each 6 px run, so the cycle is 48 px and starts again from the first when he stops | 10 |
| Jump | off the ground, rising or falling, and after an air jump | 10 (legs thrown wide) |
| Landing | for 1/8 s after touching down | 7, rows 3 to 9 |

The pictures are made by hand from the sheets, each on a 10×10 grid, so they are an interpretation of the sheets rather than a trace: every choice is in `freddy_sprites.gd` and easy to change. Where this differs from the sheets: the jump is not drawn taller than the box (the sheet's is about 12 high), so it never draws into a ceiling; the landing is 7 rows and wide only as far as the box; and the sheet's facing is only the notch and the marks (the old 2×2 block is gone).

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

**Rooms 5 and 6 are `trap: allowed`.** With double jump and no Imprint the whole world is reachable (56 of 56 ledges), but a player can cross room 5's 16-cell pit from the token platform, land on its left floor, and not get back, which makes room 6 and the door between them one-way. The user chose to mark both rooms rather than change the layout; take the mark off when a way back is built. Imprint (dev-only for now) still plays them as before.

Thirteen rooms (the first is the save room s1, and s2 and s3 are two more save rooms), as content, not as the limit of the format. The flow they make: save at the machine in s1 to leave it, take the token in room 2 to leave that, take one more in room 3 and one in room 5, spend all three at the 3TM in room 4 to get double jump (this was Imprint until double jump became the first power-up), use Imprint to cross the spikes in room 5 and then the wall in room 6, fall into room 7 beside save room s2, climb room 7 by a step, its moving platform and an Imprint to exit 1, cross room 8's two fast platforms (and its token), ride room 9's lift to its 3TM pillar (and its token), climb room 10's three lifts to its token and the exit to 11, climb down room 11's stairs and cross its lifts and slider to room 7's exit 2 (its door is closed in by a breakable wall, so it needs the gun; without it, room 10's bottom left platform leads back to room 9 with a double jump), and drop onto the platform beside the walled-in health pip, where the gun from room 9's 3TM breaks the wall. Room 10's token, carried back round the loop, is the third for room 9's 3TM, which gives the gun. Room 9's floor door drops into save room s3, whose platforms climb back up to it. Nothing leads back up to s1 yet, so rooms 7 to 11, s2 and s3 are `trap: allowed`.

```
 s1  2   3            room 2's floor door drops into 5, room 3's floor hole into 4
     5   4            5 and 4 meet at their side doors, 5 and 6 at theirs
 6                    room 6's floor door drops into 7
 7
 7  11  11  10        7's exit 2 meets 11, 11 meets the top of 10
 7   8   9  10        7's exit 1 meets 8, 8 meets 9, 9 meets the bottom of 10
s2 7                  7 meets s2 at its left door
        s3            9's floor door drops into s3
```

- **s1**, the save room, one screen at `(0, 0)` and the start room. Three tiers of platforms, each a running jump apart, and an exit in the right wall. The save machine stands on the middle platform (row 8, col 16) and the room has `exits: saved`, so the door stays blocked until the player has entered the machine's zone and been saved. The zone fills the platform's width (cols 14 to 18). It is the movement test, and the place a player comes back to when they die with no health.
- **2**, one screen at `(1, 0)`. The landing from s1's door, steps down to the right, a hole in the floor (cols 23 to 27) that drops down to room 5, and a door high in the right wall at the end of a ledge (row 9, cols 25 to 30), reached by a jump from the lower platform. It has `exits: pickups` and a token on the first platform, so it cannot be left, by any of its three doors, until the token is taken.
- **3**, one screen at `(2, 0)`. Its two-cell door and entrance ledge line up with room 2 (door rows 7 to 8, ledge row 9, cols 1 to 8), so crossing between them stays level. A hole in the floor (cols 5 to 10, mostly under the ledge) drops down to room 4. A staircase climbs from the first step (row 14, cols 13 to 17) to platforms on row 10 (cols 22 to 27) and row 6 (cols 26 to 29), then back left to the token platform (row 5, cols 18 to 21). The upper platforms are too far right for a jump from the entrance ledge, so the player still has to descend and climb the staircase. Its first step also climbs back onto the ledge, for the way back to room 2.
- **4**, one screen at `(2, 1)`, under that hole. Three platforms step down from under the ceiling door, each 4 cells apart, so the door is a short climb in and a short climb out. The 3TM (`upgrade=double_jump value=1`) stands at the bottom left, beside the left door that leads to room 5.
- **5**, one screen at `(1, 1)`, with doors in the ceiling (up to room 2), the right wall (to room 4) and the left wall (to room 6). A pit of spikes 16 cells wide, with a short floor on its left, is too wide to jump. Three platforms climb from the right-hand floor back up to the ceiling door, and a token sits on the middle one. A player standing on the middle platform can cross the pit by putting an Imprint platform in the gap, and can cross back the same way. It is the first room that is open or shut by an ability.
- **6**, one screen at `(0, 1)`, through the door in the right wall of room 5. The floor opening (columns 5–12) is covered on the player's side by a roof (row 11, columns 9–13) and a wall (column 13, rows 12–16), six cells tall including its roof, taller than a jump, so a platform put down by the wall is the only way up onto the roof, and from there the player walks off the end into the hole.
- **7**, one screen wide and four tall at `(0, 2)`, under room 6's hole, from the user's drawing of its new version. The ceiling opening is at columns 5–12. A wall in column 14, rows 1–58, keeps the fall on the left, so it cannot land on the ledges on the right; it lands on clear floor at the bottom (columns 1–13 above floor row 71) or on a step (row 67, columns 9–13) under the wall's foot, with a left door to s2 on rows 68–70. Spikes cover row 70, columns 15–30. The moving platform `r8_lift` is 5 cells wide on row 63 (four above the step), starting at columns 15–19 and moving right to the wall and back at 75 px/s. Exit 1, rows 50–52 of the right wall, leads to room 8, over a ledge on row 53 (columns 26–30) that is reached from the platform with an Imprint put down while riding. Exit 2, rows 32–34, comes in from room 11 over a ledge on row 35 (columns 24–31, shortened by two cells from the left); the health pip `r7_health` is in a box on the left of it, which nothing reaches from below, with any Imprint, and a breakable wall closes it in (see below). The `P` at column 7, row 70 starts isolated tests. It is marked `trap: allowed`, because nothing leads back up yet. The health pip box: a solid roof on row 28 (columns 14–20), the breakable wall `r7_pipwall` in column 20 (rows 29–43, floor to roof), a floor on row 44 (columns 15–20, flush with the wall so nothing sticks out), and the pip at (17, 43). The player stands on the exit-2 ledge (row 34 standing, from column 24) and shoots left along row 34: three hits break the wall and open the box, which they then jump into. Walking off the ledge instead drops past the box into the lower room. A 3TM and a title card during the fall are still planned. A small stepped ledge hangs under exit 1's ledge (row 54 col 26, row 55 cols 24–26), so the jump from the moving platform to the ledge is shorter.
- **8**, one screen at `(1, 4)`, right of room 7's exit 1. Its door to 7 is at its floor (rows 14–16) on a safe strip (columns 1–8); spikes cover the rest of the floor and its right wall (column 30, rows 1–2 and 7–16), drawn pointing left. Two platforms at 100 px/s, faster than the player runs: `r8_lower` on row 14 going right and `r8_upper` on row 12 going left. The door to 9 (rows 3–5) is over a ledge on row 6 that the upper platform never passes under, so it takes an Imprint put down while riding. From that ledge an Imprint reaches the token `r8_token` on row 3.
- **9**, one screen at `(2, 4)`. Its door from 8 (rows 3–5) is over a ledge (row 6, columns 1–4) beside the lift `r9_lift` (columns 7–10, rows 2 to 10, 60 px/s). The floor is spikes but for a pillar (column 24) whose top (row 10, columns 23–25) holds the 3TM `r9_3tm` (`upgrade=gun`). The pillar is too far from the lift for a jump: an Imprint put down while riding crosses. From the pillar an Imprint reaches the door to 10 (rows 1–3, over a ledge on row 4) and the token `r9_token` floating above. A floor door (row 17, columns 1–4) drops into s3; the spikes are cleared from columns 1–8 of row 16, so the landing and the strip beside it are safe floor.
- **10**, one screen wide and two tall at `(3, 3)`. The door from 9 (rows 19–21) drops onto a safe floor. Three lifts at 60 px/s climb left to right: `r10_lift1` (columns 8–11, rows 27–32) from the floor, `r10_lift2` (columns 15–18, rows 20–28) only from lift 1, and `r10_lift3` (columns 22–25, rows 11–21, drawn at its bottom so it moves against lift 2) only from lift 2. From the top of lift 3 an Imprint put down while riding reaches a shelf (row 6, columns 1–12) under the door to 11 (rows 3–5), with the token `r10_token` on it.
- **11**, two screens wide at `(1, 3)`, from the user's drawings. The door from room 10 (rows 3–5 of its right wall) opens onto stairs going down to the left, solid underneath: steps topped on row 6 (columns 53–62), row 9 (47–52) and row 13 (41–46), rises of 3, 4 and 4 cells, then the floor. The left screen is the way to room 7: a floor of spikes (row 16, columns 12–28) under a ceiling of spikes (row 1, columns 12–28); `r11_lift` (columns 24–28) rising from row 13 to row 3, one cell under the ceiling spikes; `r11_slider` (columns 13–18 on row 15) sliding right over the floor spikes to column 28; a pillar (columns 10–11, rows 11–16) with spikes on its top (row 10) and up its right side, and the lift `r11_pillar` just above the top spikes (from row 9), rising to row 2; and the safe floor left of it (columns 1–9). All three move at 60 px/s. The door to room 7's exit 2 (rows 14–16 of the left wall) is closed in by the breakable wall `r11_doorwall`, an L of a roof (row 13, columns 1–5) and a post (column 5, rows 14–16), so leaving toward room 7 needs the gun. There is no softlock: from room 10's bottom left platform a double jump reaches the door back to room 9, as the user found in play.
- **s2**, a save room, one screen at `(-1, 5)`, left of room 7's bottom screen. It is empty but for its save machine, which stands on the floor in the middle (row 16, col 16), and a door at the floor in the right wall (rows 14 to 16) back to room 7. Its exits are open, so saving is a choice. It is marked `trap: allowed` like room 7, because its only door leads there; they, and rooms 8 to 11, lose the mark when a way back up to s1 is built.
- **s3**, a save room, one screen at `(2, 5)`, under room 9. A ceiling door (columns 1–4) lines up with room 9's floor door. The save machine stands on the floor (column 16), and three platforms four rows apart (rows 13, 9 and 5) zigzag up to the door. It is `trap: allowed` and does not hold its doors shut.

### Starting in a room

For testing, the game can begin in any room: `--room=<id>` on the command line, `?room=<id>` on the web, or F4 while dev tools are available. F4 enters an isolated session. The player is put on that room's `P`, or just inside its first door if it has none. An unknown id is reported and the start room is used.

### Dev playtesting

F2, or Dev tools in the pause menu, opens a paused panel with Player, Rooms and Loadouts tabs.
Tools are always available in editor/debug runs. The browser release uses
`?dev=1` (for example `?dev=1&room=7`), and native exports use `--dev`. Without the
opt-in, exported gameplay has no cheat UI. F3 remains the performance readout;
F4 opens room search. This opt-in is convenience, not a security boundary.

A direct dev launch starts fresh progression and does not access the normal save.
Entering from normal play copies current progression and leaves the player where
they are. The panel can set tokens (0–3), health pips held and the bar's length (max pips; more held than the bar is long lengthens it), the gun (on or off, shot cooldown and speed), air jumps (0–3; 1 is double jump, and changing it never clears placed Imprints), Imprint unlocked,
width, seconds, active count and cooldown in either direction. Bounce says “Not implemented.”
Apply commits a validated draft atomically. Resume / Cancel or Escape closes and
discards unapplied edits. Closing keeps the test active, and the pause menu shows `Dev: not saving` (with the switches that are on).
Imprint-setting changes clear placed Imprints and any running cooldown; resource-only changes do not.

The room picker opens with every loaded room listed, visited or not, in natural ID
order, and the current room selected. Click a listed room to choose it, or type to
filter the list. Room and loadout lists grow to their full height inside the tab’s
single scrolling page; neither adds an inner scrollbar. Imprint’s switch text says
On or Off to match its current staged value, including when reopening the panel.
Start test captures current test progression and uses the selected loadout at the
room's normal test spawn. Start fresh test first clears progression. Retry test
restores that original room and captured flags, machine fills, visited rooms,
map zoom and save-room selection, with the latest explicitly applied powers and
resource counts. Later pickups and consumed tokens/health do not rewrite the
selected loadout. A rebuilt scene resets Imprints, effects, motion and platform
clocks, rather than trying to replay a mid-animation frame.

Three optional switches start off. Retry original test on death plays the normal
shatter, then restores the attempt, including its chosen health. Off uses normal
health/death rules. Bypass door requirements removes physical blocks and exit
locks, retaining ordinary transitions and destinations; it sets no flags. Turning
it off recomputes actual requirements and is refused while the player overlaps a
door that would close. It never opens sealed boundaries. Classic Imprint (no
shrinking), on the Player tab, makes platforms placed from then on keep their
full width and show the old dash clock, so the two can be compared at any time.
It is a session switch like door bypass: it survives retries, is not saved, is not
in named loadouts, and End playtest or a fresh boot turns it off. It is a
comparison, not progression, so it is not an ability and not in the catalog.
Turning it on or off clears placed Imprints and any cooldown, so platforms of the
two kinds never stand together. Normal play always shrinks.

Show token marks on Freddy, on the Player tab, draws the token marks described under Things in rooms (a black line cut out of the body for each token carried) and is off by default. It is the only way to see how many tokens are carried on the body; it does not show the Imprint line, which is never drawn. It takes effect at once, with no Apply. Like Classic Imprint it is a session switch: it works only in a dev test, survives retries, is not saved, is not in named loadouts, is not an ability and not in the catalog, and End playtest or a fresh boot turns it off. The pause menu's status line says "token marks" while it is on.

Wall strength, on the Player tab, is how many shots break a breakable wall (1 to 99, 3 by default). Type a number and press Enter, or use - and +; it takes effect at once, on the next hit, with no Apply. Like Classic Imprint it is a session setting: it survives retries, is not saved and is not in named loadouts, and End playtest or a fresh boot resets it. It is not an ability, because it is tuning of the world and not something the player has, so it is not in `Abilities` or the dev catalog. Outside a dev test a wall always takes 3.

Named loadouts store powers, tokens and health in `user://dev_loadouts.json`,
version 1, independently of the normal save. Selecting stages a draft; Apply uses
it. Save new, Update, Rename and Delete are explicit actions. Loadouts contain no
room, progression flags, machine state or override settings. New fields acquire
current defaults; removed abilities/effects are reported. Invalid or newer stores
remain untouched and failures are shown without stopping the current test.

No test reads, writes, erases or migrates `save.json`, even after a save machine or
with `new-game` also supplied. Save machines show no “Game saved” line. End playtest
destroys the test world before normal save access returns, then resumes the normal
save or a fresh normal game if absent. Launch arguments are consumed for this
in-app return; refreshing a URL still containing `dev=1` starts another test.

The panel waits for a busy animation or map to close, saying nothing; a second F2 cancels pending
opening. Map/panel pause ownership prevents one from unpausing the other. Gameplay
input waits for held keys/buttons to be released, and panel clicks cannot place
Imprints. The pointer is visible while editing. Panel styling stays monochrome.

**Menus and overlays** are presentation and progression-neutral, so they have no dev control, by design. The title card replays in every room or dev test session (a fresh world each time). A power popup shows on a real pickup or 3TM grant in a test session and never on a dev panel edit. The `title:` flags are not read by `ExitRules` or the solver.

### Checking rooms

A room is not finished when it loads. `tools/validate.sh` also plays the whole world with the movement simulator, starting from the `P` in the start room, and fails if the world cannot be played.

A **ledge** is a run of cells with air above and floor below. From each ledge the solver tries walking off either end, and jumps from every cell with the input held left, none, or right, and the jump held for a tap, a hop, or the full leap. Each try is the same `MovementSim` the player runs. A try that lands on another ledge, or touches a door, is an edge in the graph. A try that touches a door records the body's position and velocity there. `Door.crossing`, the same function the game uses, says where that body appears on the far side, and the solver lets it fall or walk from there to see which ledge it lands on. A body that touches spikes is dead, so a path through them is not a path. A body that falls through a door keeps falling to the bottom of the room it lands in, however tall: room 7 is four screens high.

- **Error:** a room, or a door in a reachable room, that no path from the start reaches.
- **Error:** a door that every body going through it lands on nothing after, because the room beyond has a void or only spikes under it. The check is that some entry lands on a ledge. It does not promise that every entry does, so a shaft can still be hard to climb out of: play it.
- **Error:** a trap, meaning a ledge the player can reach but from which no path leads back to the start. Falling into a pit too deep to jump out of is one. The first version of room 3 was one.
- **Error:** a pickup, token, 3TM or save machine in a reachable room that no sampled path touches. A path that touches it and then dies on spikes still counts, because the pickup was taken. Only paths that start on a ledge are tried, so a pickup that can be taken only by falling through a door onto it is reported as out of reach.
- **Error:** a room whose exit rule is never met. Its doors never work, so everything past it is out of reach and its own floor is a trap.
- **Warning:** a ledge in a room that says `trap: allowed` with no way home, and the door that nobody inside such a room can touch. A room can say it in its header when it is meant to be a one-way drop (room 7 and save room s2 beside it, until room 7's way out is built). It still has to be reachable from the start, and nothing else about it is relaxed.
- **Warning:** a ledge nobody reached. The solver tries a fixed set of inputs, so a ledge it misses might still be reachable by a path it did not think of. Look at the render and decide.

`tools/render.sh` draws each room and the world map to `build/renders/`. Red bars mark unreachable ledges, yellow bars mark traps, and orange marks a door that was sealed. A moving platform is light blue where it starts, with its track as blue dots.

**Moving platforms in the solver.** Each moving platform is a ledge of its own in the graph, named "the moving platform <id>", so the ledge counts include them. The jumps from a ledge near a track are tried with the platform moving, starting at moments spread over its whole trip: every 12 ticks, or every tick it takes to move a cell if that is sooner (`ReachGraph.phases`, 25 moments for room 7). A jump that lands on the platform at any of them is an edge to it. Once on it, the player can ride it to any moment, because nothing is allowed in the row a rider stands in, so the jumps and the walks off either end are tried from every spot on it at all of those moments. Riding sweeps that row, so a pickup standing in it is taken. A moving platform nobody reaches is a warning, like a ledge. The platform phase checks are kept by the cache after the first run. A rider can also put an Imprint down: the Imprint search tries the rider's jumps from the same spots and moments, with the platforms moving, and checks each candidate with them moving. Left out: the jumps off a placed Imprint (its legs) pass through moving platforms and never land on one, and a body falling into a room through a door does not land on one.

**Imprint in the solver.** The solver takes the player's `Abilities`. With Imprint unlocked, a ledge gets extra edges: a player standing there can put a platform down, jump onto it, and jump from it.
- It does not try every platform. From each ledge the usual jumps are simulated once, and a platform is a candidate only where one of those jumps comes down through the top of a cell row, and only if it is a legal place (the same `ImprintRules` the cursor uses) within a jump of something still out of reach. Each candidate is then checked by simulating the jump again with the platform in place. A platform that passes is searched from like a ledge of its own.
- A platform lives `imprint_duration` seconds. The jump onto it has to land within that life less `SPARE_TICKS` (40 ticks, to stand on it and push off), 50 ticks at the starting 1.5 s. The jump off it is an ordinary ledge's, because once the player has left it they no longer need it. A one second platform (20 ticks) crosses nothing, and one under two thirds of a second is gone before any jump can land.
- **The lockout and the cooldown need no model in the solver.** It puts one platform down at a time, never two in a row, then carries on from the ledges that exist afterwards. Waiting for a platform to break, and for a cooldown to pass, is always possible on a real ledge, and on a moving platform too: a rider can wait on it for any moment, because the row above it is kept clear and it never crushes a rider or carries them through a door. That argument is why a feature that makes waiting costly (timers, crumbling floor, chasing hazards) or that gives more footing has to say how it keeps the Imprint rule (see Guardrails).
- A ledge that cannot get home is searched the same way, with the ledges that can as the targets, so crossing a pit one way with a platform and having no way back is still a trap.
- Left out: putting the platform down in mid-air, and using two in a row. A room that needs either is reported as out of reach even if a player could do it. A room that needs the platform in a place the reach check calls out of reach is also not found.

**What a room needs.** `tools/validate.sh` solves with the starting abilities, takes every pickup that solve could reach, solves again with what they gave, and repeats to a fixpoint, when nothing new turns up or the newly reached things do not change the abilities. The number of things in the world makes this finite; if the search ever fails to settle within that bound, validation fails instead of accepting a partial answer. A room, a ledge, or a pickup that only opens in a later round lists the pickups it needs, cut down by dropping them one at a time to a set it still opens with. Example, from the current world: `Room 5: the ledge on row 16, cells 0-4 needs r2_token, r3_token, r4_3tm, r5_token`. Errors come from the last solve, so a room that stays shut even with every pickup is an error. Tokens and 3TMs are part of this. A save machine reached sets the flag that opens `exits: saved`, and gives nothing, so it never changes what a room needs. A token reached is taken. A 3TM reached gives its upgrade if three tokens are taken for it, and several machines are paid in the order of their ids. A room with an exit rule keeps its doors shut in the search until what the rule asks for has been reached, so a room is only open if the player can first do what it asks. The search does not model the carry limit of three (a player who cannot take a fourth token before spending three is not caught), and it does not treat a blocked doorway as a wall for a body falling through a chain of doors. A trap is judged where the player could first be in it, with the fewest abilities, because a player who has not found Imprint yet is also stuck in a place that needs it to leave.

**Speed, and the cache.** Before the merge, a cold run was about 32 s for 9 rooms, and most of it was the Imprint search: each ledge's jumps (about 5 s, 3 of them room 8's moving platform) and, for every platform Imprint could put down, a check that the jump lands on it (about 6 s) and a "leg" of about 40 simulated jumps from it (about 19 s). What the solver works out about a room depends on nothing but the room and the solver, so it is kept between runs in `build/solver-cache/<room>.json`: the jumps from each ledge, and each platform's leg by cell, width and length. A room's file is used only if two fingerprints match: the room's (its grid with the openings that lead nowhere sealed, its doors and where they lead, its things, where it sits, so a neighbour that appears or moves counts) and the solver's (a hash of the code and numbers that decide a jump: `reach_graph.gd`, `imprint_search.gd`, `movement_sim.gd`, `movement.tres`, and the others listed in `SolverCache.SOLVER_FILES`). Change either and that room, or every room, is worked out again. What is not kept is cheap and depends on more than one room: where a door leads, and the search that spreads out from the start. A warm run is nearly all the landing checks, which are not kept. Before the last-block model it took about 8 s on the user's machine (11.8 s measured in the cloud, against 52 s cold); the second simulation each landing arc now needs makes the landing checks about three times as long (landings 8.6 s to 25.7 s), so a warm run measured in the cloud is 29.4 s against 55 s cold (the legs got cheaper, being one block wide and shared across widths: 33 s to 19 s cold). Caching the landing checks, or skipping the second simulation for an arc whose path never comes near an outer block, would bring it back down; neither is done. Adding rooms 7 to 11 (four more rooms, six more moving platforms, five more things to take, so more rounds) took a warm run to 185 s, nearly all of it landing checks repeated in every round; keeping them for the solve (`_landed`) and thinning a rider's tries brought it to about 28 s warm and 118 s cold on the user's machine. A run after editing one room redoes that room's share. A file that cannot be read is ignored. The tests never read the cache. `tools/validate.sh --no-cache` ignores it too, and prints the same answers.

Threads were tried first and are not used: GDScript's simulation only runs about 1.5 times faster on two or four threads, and slower on eight, so an Imprint search on all cores saved about 15%.

## Camera

The camera shows one screen, and it stays inside the room.

- A room that is exactly one screen locks the camera to the room's center. It never scrolls.
- A wider or taller room follows the player, clamped so the 320×180 (world pixel) view never leaves the room, then rounded to whole world pixels.
- The follow target is the player. During a door slide, follow is off until the slide finishes.

## Map

Hold Tab or M. The game pauses. A dim covers the playfield over about 0.1 s, and a panel scales from 0.92 to 1. Releasing the key dismisses it.

Visited rooms are outlined rectangles. In dev mode (dev tools available: editor and debug runs, or `?dev=1` / `--dev`) the map always shows every room in the world, visited or not, a door connects to every room it leads to, and each room has its id written small in it, white on a black edge, for reference. Normal play shows only the visited ones. The current room is filled. The player is a blinking pixel. Exit gaps break the outline where the doors are, and a connector joins a door to the door it leads to. The connector is drawn once the room on the other side has been visited.

A room that spans screens is one rectangle, not a row of separate rooms. The gap that normally separates neighboring rooms is filled in across the screens that room owns, so the shape on the map matches the continuous space. Door gaps and the player marker are placed per screen, so a door on the second screen sits on the outer edge of that wide rectangle, in line with a one-screen neighbor.

The room layer is drawn into a viewport and redrawn when the current room changes, a new room is visited, or the zoom changes. Each frame after that is the texture plus the marker.

**Zoom.** While the map is held, Up or W zooms in and Down or S zooms out, one level per press, stopping at the ends. There are three levels:

- **Out** shows every visited room, however big the map gets. It never zooms in past Middle, so a small map looks the same at Out and Middle. It is centred on the visited map.
- **Middle** is the view the map always had: centred on the current room, clamped when the map is larger than the panel.
- **In** is twice that, centred on the player's marker and clamped to the map.

The map is redrawn at each scale and not stretched. Every corner is scaled and rounded to a whole pixel, and lines stay one pixel thick, so outlines and door gaps are as sharp at every level and rooms that touched or had a gap keep that. The level is part of the saved game (see Saving), and the map opens at the level the player left it at.

**Legend.** In the bottom-right corner of the map, two rows of symbols and no words, on a small black patch: an up arrow beside a magnifying glass with a plus (zoom in) over a down arrow beside a magnifying glass with a minus (zoom out). A row that can do nothing more, because the map is at that end, is drawn grey.

## Look, and the softer palettes

Built today: pure black background and solid white geometry. The player, Freddy, is lime `#C6FB65` with a yellow patch, white eyes and black pupils and marks. Glows and the map dim use ordered dithering or alpha. The map's current-room fill is an opaque gray, because a translucent white is premultiplied twice in the web build and disappears.

Designed, not built. Pure black and white stays the way art is drawn. One full-screen pass at the end of the frame remaps brightness onto a two-color palette: `mix(background, foreground, luma)`. No sprite is recolored by hand. The halo dither, the map dim, and any future sparkle or shatter pick up the palette because they are already shades of the same image.

| Palette | Background | Foreground | |
| --- | --- | --- | --- |
| Paper and Ink | `#1E1C1A` | `#DCD3C1` | Default |
| Amber Terminal | `#1B1612` | `#D9B27C` | |

Both are about 10–12:1 contrast, down from 21:1 for pure black on white. P cycles them. The choice is saved and restored, including in the browser. The page behind the canvas uses the same background, so the letterbox matches.

The build steps for that pass are in `docs/plans/soft-duotone-palettes.md`.

## Imprint

Status: built: finding it (three tokens at a 3TM), placing it, the reach check, the lifetime and how it shrinks, and the rules below. The solver knows about it, so `tools/validate.sh` proves which rooms are open or shut by it. Width, duration, the cooldown, and multiple active platforms work in the runtime and can be set through dev tools, though current rooms award none of them. Bounce is only a stored effect name; its behavior is not built.

Imprint is the ability that makes Freddy's Fall a metroidvania. The mouse cursor is a platform. The player places it, jumps from it, and uses longer, longer-lasting, and stranger versions of it to open paths that the authored rooms withhold.

### Fantasy

The cursor is a promise of a foothold. Before the click, the player can see whether that foothold is one they can actually reach. After the click, it is real for a few seconds, and then it breaks.

### The platform

The cursor snaps to a cell. That cell is the platform's left edge. The platform is `width_cells` wide and one cell tall. It is never rotated and never placed between cells. It shares edges, heights, and jump distances with the authored platforms, which are about four or five cells wide.

At the start, `width_cells` is 2: the player's width plus one spare cell. The width goes to 3 through the `imprint_width` upgrade (room 9's 3TM gave it before it became a health pip), the player's width plus a spare cell each side. The width is the size a platform *starts* at; it shrinks (see below).

### Placing

Left click places the platform under the cursor. There is no keyboard or gamepad way to place one yet. One is planned, not built: see "Aiming without a mouse" below. The code gets the target cell from one function, so another input can feed it later.

- **An Imprint is never replaced.** The starting limit is one (`imprint_max_active`), and while that many stand, a click does nothing, however often it is made. The next may go down only once the live one has broken on time (when its last block goes), plus `imprint_cooldown` seconds. The cooldown starts when a platform finally breaks, not when a block of it goes, and is 0 by default, so it is off in real play and is only tried through dev tools (0.2 s is the value to try). Leaving a room, dying, warping and applying a change in the dev panel clear the platforms and the cooldown. No current room awards a larger limit or a shorter cooldown.
- **Why.** Replacing let a player click again and again and keep one platform alive for ever, which walks around any puzzle that is meant to be solved in the platform's lifetime. The starting duration is 1.5 s.
- It has to lie fully inside the current room. The room is the whole room, including every screen it spans, not the visible viewport.
- It cannot overlap level geometry, spikes, or a door's trigger zone and the cell around it, so it cannot wall off a doorway or cover spikes.
- It cannot overlap the player.
- A `~` cell refuses it. That is how a puzzle can forbid the obvious ledge without changing the jump rules. `~` cells are not drawn: the player finds one by being refused there.

A platform may sit just above spikes. Bridging a spike pit with a platform a few cells over it, to jump from, is a core puzzle.

A placed platform is solid on every side, like authored floor. It can be stood on, bumped from below, and walked into. When it breaks under the player, they fall.

A legal placement lasts `duration` seconds, 1.5 at the start, and the platform is its own clock: it gets smaller, one block at a time. Each equal share of its life (the life divided by the width it started with) one block goes. At width 2 and 1.5 s a block goes every 0.75 s; at width 3 every 0.5 s: three blocks until 0.5 s, two until 1.0 s, one until 1.5 s. The total time never depends on the width.

**The order is set at the click, from where the player is, and never changes after.** The block farthest from the player's centre goes first, and the block nearest them goes last, so in the last share the platform is the one block closest to where they stood. Placed by a player to its left, a 3-wide platform goes right, middle, left; placed from its right, left, middle, right. The farthest block is always an end, so the platform stays in one piece. When two blocks are exactly as far (a player standing right under the middle of a 3-wide platform, or on the line between the two blocks of a 2-wide one), the block **behind** the player goes first, so the one they face lasts longer. Moving after the click changes nothing.

The block that goes next blinks, every tenth of a second, for the last 0.25 s before it goes (never more than half a share, so a very short life is not blinking all the time). Its footing stays until it goes. Each block that goes shatters into pixel shards where it stood, and the last block shatters as the platform ends. Nothing fades.

A placed platform is a white block with a **1 px black dotted border**, drawn 1 px inside its edge, which follows the platform as it shrinks. The border means "you placed this", and it is not the white dotted cursor outline.

### Reach, before the click

The cursor has two looks: a dotted outline of the platform wherever one may go, and a small × where one may not. For now the outline is the same whether or not the player can reach it. (It used to be filled, with a sparkle, when they could. That may come back.)

The game still works out, before the click, whether some jump the player can perform from their current position lands on the platform's top, so the look can show it again without new work.

The check includes being in the air. It starts from the player's real state: on the ground, or airborne with their current velocity. It tries a small set of jumps, not every possible input: hold left, hold nothing, or hold right, and release the jump at a few different times. Those paths use the same movement rules as the player, against the room's solid rectangles. If any path lands on the candidate platform's top, it counts as reachable.

The check runs again only when the player's cell, the cursor's cell, or whether the player is on the ground changes. Moving inside a cell does not recompute it.

- **Unavailable.** An illegal cell (outside the room, overlapping geometry, spikes, a door or the player, or marked `~`) is not a placement. No platform is drawn there, only a small ×, so it is never mistaken for a legal platform that merely cannot be jumped to. Clicking does nothing.

The operating system cursor is hidden while Imprint is available, because the preview is the cursor.

### What it is for

Imprint is the gate, the puzzle, and the traversal tool.

- A gap wider than a running jump is closed by a platform the player can reach and place. A wider platform buys landing time and room, but the block a puzzle can count on is the last one: the player has to be on it, or off it, by the end.
- A route that needs a wider platform, a longer-lived one, or a platform that bounces stays closed until that upgrade is found.
- A `~` region is a place the designer has decided must be crossed some other way.
- Once the one platform is placed it stands until it breaks, so a puzzle can require the player to choose which gap to bridge and to wait for it.

Authored rooms should be solvable only with the upgrades available up to that point. The check the cursor uses is the same idea as the test that proves a room's own jumps: if the cursor says a platform is reachable, a player who jumps the way the check assumed can land on it.

### Finding it

The player does not start with Imprint, and for now normal play does not give it: the 3TM in room 4 gives double jump, and Imprint is unlocked only in the dev panel. The plan is that it is earned later. A token lies in room 2, which cannot be left until it is taken, one more lies in room 3 and one in room 5, and the 3TM in room 4 takes all three. Once Imprint is unlocked the cursor is a platform, and a line appears across the player's body.

Tokens are the currency for upgrades, and a 3TM is the shop. Tokens are scattered through the world to be found by exploring, up to three at a time in the pocket, which puzzles are built around. Each 3TM is set to give one upgrade, so later upgrades (the ones below) mean placing more machines. How many tokens each costs is three for now.

### Upgrades

Upgrades are pickups in the world, written into a room's legend and drawn with their own character, and kept on the player once collected, and in the save. Leaving a room does not take them away.

| Upgrade | Starts at | Grows to |
| --- | --- | --- |
| Width | 2 cells | 3 at room 9's 3TM, later 5 |
| Duration | 1.5 seconds | longer |
| Cooldown | 0 seconds (off) | shorter, if a later upgrade ever does; none exists, and it is tried in dev tools |
| How many at once | 1 | stays 1 unless a later upgrade says otherwise |
| Behavior | a still platform | bounce, and others after that |

Width, duration, and behavior are the three things a room can demand. A later room can need five cells of width, or a platform that lasts long enough to cross two jumps, or a bounce, and the layout is what enforces it. There is no separate key item.

Bounce is the first special behavior. Others can be added the same way: a property of the placed platform, found as a pickup, and required by some later gap.

Imprint is not given by any room now, and neither is the platform 3 wide that room 9's 3TM once gave. Upgrades not awarded by current rooms; they work in the runtime and can be tried in dev tools:

- A platform wider than 3.
- More than one platform at a time. Several then stand together, up to the count. A click is still refused at the count, and never replaces one.
- A longer life for the platform.
- A shorter cooldown (a `min` upgrade, which keeps the smaller value). It works in the runtime and in dev tools; no room awards it.
- A bouncy platform.

The starting values are the defaults in `Abilities` (`src/core/abilities.gd`): width 2, duration 1.5 seconds, one at a time, cooldown 0, no special behavior, and Imprint itself locked. They live in `GameState.abilities`, and the width and duration are read when a platform is placed.

### Look

Imprint uses the same black-and-white pixel language as the rest of the game.

- Dotted outline: a platform can go here.
- A small ×: you cannot put one here.
- A white block with a black dotted border inside its edge: a platform you placed. It gets smaller one block at a time, the block farthest from where you clicked from first, and the block that goes next blinks. (In Classic mode, a dev comparison switch, it stays full width and has a dashed line through it that counts down, with the last dash blinking.)
- A placed platform is always drawn over the cursor, so what the player can land on is never hidden by the preview.
- Shatter into pixel shards: it is gone.

The shards are small. They should read at 320×180 world pixels and survive the softer palette, because that palette remaps the frame rather than the sprites.

### Aiming without a mouse (planned, not built)

Status: planned, not built, and not scheduled. Nothing below is in the game. A concept video was recorded in the engine on 2026-10-26 from a throwaway prototype, kept with the video in `tools/concept/`. When this is built, this section becomes the spec and the rest of "Imprint" is updated to match.

**Why.** Moving a mouse to an exact cell in the middle of a jump is slow and hard to learn, and the puzzles want a platform in a split second. A gamepad has no pointer at all. Controller support is the long-term goal, so placement has to be something a stick and a button can do.

**The idea: fixed slots.** A platform can only go in a small set of places relative to Freddy: five directions, each with a near and a far slot. Placing is then one press, and every place is learnable.

The offsets are counted from Freddy's own cell: his centre column, and the row just above the first row wholly under his feet. So row +1 is the floor row when he stands, and the first clear row under him in the air. The offset names the **anchor block**, the one nearest Freddy, which is the one that lasts (see the shrink order above). The rest of the platform extends away from him. Facing left mirrors every slot.

| Direction | Near | Far | Use |
| --- | --- | --- | --- |
| Forward (or nothing held) | 1 ahead, on the floor row (+1, +1) | 4 ahead (+4, +1) | extend a ledge, bridge a gap from its edge |
| Up-forward | 2 ahead, 1 up (+2, −1) | 4 ahead, 3 up (+4, −3) | a step up; the top of a full jump |
| Up | 1 ahead, 3 up (+1, −3) | straight up 5 (0, −5) | a high perch |
| Down-forward | 2 ahead, 2 down (+2, +2) | 4 ahead, 4 down (+4, +4) | a landing pad for a drop |
| Down | under the feet (0, +1) | 4 down (0, +4) | catch a fall |

These are starting numbers, kept in one data table that the runtime and the solver share. They are expected to change in playtesting. The concept first had forward near at +2 and far at +5. Near at +2 left a one-cell hole at a ledge's edge. Far at +5 meant a jump to it landed on the far block after that block had gone.

A slot that is not legal (`ImprintRules.check`: a wall, spikes, a door's zone, `~`, Freddy, another platform) shows the existing small × and refuses. It never slides to a nearby legal cell. What the player sees is what they get.

**Two schemes, both to be built and switched in the F2 dev panel to compare.**

- **A, dash-style (the default in normal play until one is chosen).** Like Celeste's dash: hold a direction and press a button. **J places the near slot and K the far one.** While Imprint is ready, the near slot (white dotted outline) and the far slot (grey) for the held direction are always drawn, so the player sees both before pressing. W becomes aim-up, so jump is Space or Up only.
- **C, build mode.** Hold Shift (LT on a pad). Time drops to 30% and every slot lights up. The held direction selects the slot nearest that way, and tapping it again steps out to the far one. Letting go places it. It opens only when a placement is allowed (no platform standing, no cooldown). It lasts about 1 s of real time at most, and it ends on release, on that cap, on death, on a door and on opening the dev panel.
- **Free aim (classic, dev only).** Today's free mouse aim. It stays only as the third F2 choice, for comparison.
- **The mouse** stays as an input in A and C, but a click places at the slot nearest the cursor, so mouse players keep the same rules.
- **Near and far are both available from the start.** There is no upgrade for the far ring.

| Action | Keyboard | Pad |
| --- | --- | --- |
| Move, and aim | A / D, and W / S | left stick or d-pad |
| Jump | W, Up | A |
| Imprint near / far (A) | J / K | X / Y |
| Build mode (C) | hold Shift | hold LT |

**The Imprint rule is unchanged.** Still one platform, never replaced or refreshed, and the next only after it breaks plus `imprint_cooldown`. The shrink order is still set at the press, from where Freddy is. Build mode cannot be used to get around it, because it only opens when a placement is already allowed.

**What it changes in the solver.** Today the solver places a platform from a ledge onto any cell a jump crosses (see "The solver"), and mid-air placement is left out. With slots, a placement is a press at some tick of a jump, times a slot relative to the body at that tick. So mid-air placement has to be added to the search: sample press ticks along each arc, take the slots there, check them with `ImprintRules.check`, and verify the landing on the last block as now. There are far fewer candidates than the current sweep of every cell. The slot table joins the solver cache's hash.

Rooms built for free aim may stop solving, especially any that rely on a platform placed far from Freddy. `tools/validate.sh` will name them. They are reported to the user and are not redesigned without asking.

**What the concept showed.**
- **Forward slots do not catch a fall.** Freddy falls about 5 px a tick and moves 1.5 px a tick sideways, so a platform placed ahead and below in mid-fall is already above him by the time he reaches it. Down and down-forward are the slots for falling. Forward is for use from a ledge.
- **The far block of a forward slot can be gone before the jump lands.** A puzzle should count on the anchor block, as it already does.
- **Godot's `Engine.time_scale` keeps 60 physics ticks a second and shrinks each tick's delta.** `MovementSim` and the solver assume a fixed tick, so build mode's slow-down must be done another way that keeps the runtime and the solver in agreement. One way is to step physics less often.

**Dev tools, when built.**
- An "Imprint aim" choice in the F2 panel: dash-style, build mode or free aim. It is kept with the dev session, survives retries, round-trips in named loadouts and never touches the normal save.
- No new ability stat, since nothing is unlocked.
- Tests:
  - slot maths: mirroring, widths 2 and 3, both rings, a refused slot, and the mouse snapping to the nearest slot
  - build mode: it is refused while a platform stands or the cooldown runs, and time is always restored
  - the solver finding a mid-air catch with down-near

## Gun and breakable walls

The gun is the second power-up, given by the 3TM in room 9. Its job is to destroy **breakable walls**, and later enemies.

**The shot.** `shoot` (Space) fires one shot a press from the player's body, straight ahead, the way they face. There is no aiming: to shoot higher, jump and shoot. A shot is a small white line (3 x 1 px). It flies at `gun_shot_speed` (260 px/s, about three times run speed) until it meets something solid, and it has no range limit and no limit on how many are in flight. It is stopped by the room's solids, door blocks, moving platforms, Imprint platforms and breakable walls, and goes when it leaves the room. Spikes, tracks and things do not stop it. A shot that stops puffs two specks back. Shots are cleared when the player changes room, dies, warps or retries.

**The rate.** One shot every `gun_cooldown` seconds (0.2, five a second): spammable to a degree, and no faster. Holding the key does not repeat; each shot is a press. The starting rate and speed are guesses to be tuned in play, and a later upgrade can raise them: `gun_cooldown` (a `min` upgrade) and `gun_shot_speed` (a `max` upgrade) exist for that, work in the runtime and in dev tools, and are awarded by no room.

**Breakable walls.** A wall is a legend kind (`B = breakable id=r7_pipwall`) drawn on every cell of one connected shape. While it stands it is solid, so a player stands on it like any platform. It looks cracked: a white block with black crack lines, so it reads as something that can be destroyed. Every shot that lands on it counts as one hit for the whole wall, flashes it, and adds cracks (three stages); at the wall's strength (3 hits, `BreakableWall.DEFAULT_STRENGTH`, tunable in dev tools) it shatters cell by cell and stops being solid. **Only the gun breaks a wall.** A broken wall is back every time the room is built (entering it, respawning, retrying): nothing about a wall is saved. So a wall gates a place for one visit, and the player has to shoot it again each time they come.

**Room 7's pip.** The health pip is closed in by a solid roof and a breakable wall (see "The current slice"), so the player can only get it once they have the gun.

**Not built yet:** enemies, per-wall strength (`hits=` in the legend), and a mark on the body for the gun.

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

`MovementSim.State` holds a body's position, velocity, `grounded`, `coyote`, `buffer`, `launched`, `cut`, `air_jumps` (the most it may make, set by its owner from `Abilities.air_jumps`) and `air_left` (refilled whenever it is grounded, and clamped down if `air_jumps` falls), `riding` (the moving platform it stands on, or -1), and, after a step, `jumped`, `air_jumped` (that jump was an air jump), `crushed` and the `floor_rect` it stands on. `step(cfg, state, rects, input_x, jump_pressed, jump_held, delta, movers, tick)` does one tick, in this order:

0. With moving platforms (`movers`, which go from where they are at `tick` to where they are at `tick + 1` during the step), `move_with`: the one the body is riding carries it by its move, and any other that moves into the body pushes it out of its leading side, both stopped by walls. A body still inside a platform after that is `crushed`. The platforms are then solid, where they are at `tick + 1`, for the rest of the step.
1. `integrate` (which also takes `air_jumps` and `air_left` and returns `air_jumped` and the new `air_left`): horizontal speed moves toward `input × run_speed` at the ground or air acceleration (or friction when there is no input); the coyote timer is set while grounded and counts down; the jump buffer is set on a press and counts down; if both are above zero a jump starts (`vy = -jump_speed`); otherwise, on a fresh press with `air_left > 0`, an air jump starts (`vy = -air_jump_speed`, `air_left` down by one, `launched` set so a release cuts it); otherwise a released jump that is still rising is cut (`vy × jump_cut`, once), and gravity is applied, scaled by `apex_gravity_scale` while `|vy| < apex_threshold` and by `fall_gravity_scale` while falling, capped at `max_fall_speed`.
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
- a **health pip** calls `GameState.take_health` (set `health:<id>`, add one to `health`), toasts the count, and the thing leaves;
- a **token** is taken if the pocket has room (`GameState.TOKEN_CAP` = 3), sets `token:<id>`, and leaves; with a full pocket it stays and says so once per visit (`noted`, cleared when the player steps off it);
- a **3TM** runs `World._feed`, a coroutine: the world goes busy; for each carried token (until the machine is full) a `FlyingToken` arcs from the body to the next slot over `FEED_TIME` (0.45 s), the slot fills and `GameState.machines[id]` is updated, then a pause of `FEED_PAUSE` (0.2 s); when the third slot fills the machine dispenses (about 0.8 s of shaking and flashing), a spark flies to the player over `SPARK_TIME` (0.3 s), and `GameState.machine_prize` gives the machine's prize (`grant` for its upgrade, or one more health for `prize=health`, with no flag, since the machine's fill is what remembers it); then control returns and the game autosaves. A machine is spent when `filled >= TokenMachine.COST`.

- a **save machine** runs `World._save_at`, a coroutine, when the player enters its zone (`SaveMachine.rect`, 5 x 3 cells) and `used` is not set: the world goes busy and the player is held (`_hold_player`); `_arc` moves them on a parabola to `SaveMachine.centre` over `HOP_TIME` (0.2 s) and they are hidden; `SaveMachine.close` shuts the halves (0.1 s); `_commit_save` sets `save:<id>` and `GameState.save_room`, runs `recheck_exits` (so `exits: saved` opens), autosaves and toasts "Game saved"; `spin` turns it (0.6 s); then `_pop` opens it (0.1 s), arcs the player to the floor two cells to the side opposite the one they entered from (0.2 s), places them there with the room's current solids, returns control, and starts the machine closing without waiting. `used` is on the node, and the room is built again on every entry, so a new visit finds the machine open. A body in the machine's 3 x 3 when it is built by a reload (`World._ready`) or a death with no health (`_respawn`) is found by `Room.save_machine_holding`, and `_emerge` shuts the machine round it, saves first if the flag is not set, spins it, and runs `_pop` to the right. `SaveMachine.pixels` is the one-bit drawing (two half discs swung about the hinge, or a ball with lines of longitude; both are filled with level lines every `LINE_STEP` (2) rows by `_shade`), and `touch_rect_for` is the zone, which the solver uses too.

After any take, `recheck_exits` runs and the game autosaves.

### The gun and breakable walls (`gun/`, `world/entities/breakable_wall.gd`, `world/room.gd`, `world/room_info.gd`)

`Gun` is a node of the world beside `Imprint`. Each physics tick, unless the world is busy, it counts the cooldown down, moves its `Shot`s, and then fires if `shoot` was just pressed (`scripted_fire` for tests). `can_fire` needs `GameState.abilities.gun_unlocked`, the cooldown run out, no modal panel or key-release wait (`World.gameplay_input_blocked`), the player in control and the world not busy. A `Shot` is plain data (position, direction, speed). The gun moves each in steps of at most `STEP` (4 px), and after each step `_hit` asks the room: `Room.wall_at(box)` first (a hit: `Room.hit_wall(wall, DevSession.wall_strength())`), then `world_rects()` (room solids, door blocks and the walls that stand), Imprint platforms and `mover_rects()`; a shot outside the room's rect is dropped. A shot starts `MUZZLE` (6 px) in front of the body, so one fired point blank against a wall hits it at once.

`RoomInfo.breakables` maps a wall's id to its cells (`register_breakable`, called by the parser, which also checks the cells are connected and not in a moving platform's track). The wall cells are not in `solids`; `is_solid` includes the ones that stand, and `all_solids()` is `solids` plus a cell rect for each. `broken` is the ids broken, and `variant(broken)` is a cheap copy of the room with its own `broken` (everything else shared). `Room.build` takes a variant of the loaded info, so a wall broken in play is broken in that one Room and the loaded room is untouched: that is why walls come back. `Room._solid_rects` (and so `world_rects` and the safe-floor rects), `ReachGraph.geometry_of` and `Door._walled` use `all_solids()`. A broken wall is erased from the room's `_walls`, added to `info.broken`, and `wall_broken` is emitted; the world answers with `imprint.sync_solids()`, which rebuilds the player's collision list. `BreakableWall` (a node at the room's origin) draws its cells and counts hits (`hit(strength)` returns whether it broke, and shatters one `Shatter` per cell). Abilities `gun_unlocked`, `gun_cooldown` and `gun_shot_speed` come from the upgrades `gun`, `gun_cooldown` and `gun_shot_speed`. Wall strength is `DevSession.wall_strength()`.

### Moving platforms (`world/platform_path.gd`, `world/movers.gd`, `world/entities/moving_platform.gd`)

The parser turns a `platform` legend glyph into a `PlatformPath` in `RoomInfo.platforms` (`_place_platform`, `_track_length`), and checks the rules around it (`_check_platforms`, and `_check_platform_doors` once the doors are known). A path holds the drawn cells, the direction, how many cells it travels, `travel_ticks` (its distance over its speed, at `TICKS_PER_SECOND` = 60) and `pause_ticks` (`DEFAULT_PAUSE` = 0.2 s). `period()` is a trip there and back with both waits. `rect_at(tick)` waits, slides linearly, waits and slides back. `swept_cells()` is every cell it covers, `band_cells()` the row above that, and `keep_out()` both, in pixels. `Movers` is a room's paths shifted to where the room is.

`Room.build` makes a `MovingPlatform` node for each path and a `Movers` at the room's position. The room runs at `process_priority` -1, so each physics tick it advances its `tick` and moves its platforms before the player steps. The player keeps the `room` the world placed it in, and steps with `room.movers` and `room.tick - 1`, so it is carried from where the platforms were to where they are now. A held player (a door slide, a save machine, a 3TM, a death) is not stepped, and stops riding. `World._physics_process` treats `Player.crushed()` like spikes. `Room.mover_rects()` gives the platforms where they are now, which the Imprint preview adds to what it checks a jump against.

### Dying and safe floor (`world/world.gd`, `world/room.gd`)

Touching spikes, or leaving the room's outline by 60 px, calls `_die`: the world goes busy, platforms are cleared with shards, the player shatters, and after `DEATH_TIME` (0.6 s, on physics time) `_respawn` puts them back. `_die` decides where: with `GameState.health` above 0 it empties a pip (`GameState.spend_health`) and `_respawn` puts them on the last safe spot, as described below; with none, `_respawn` calls `_place_in` at `_resume_point()`, the machine of `GameState.save_room` (its `RoomInfo.save_cell`) or else the start room's `start_position()`. That placement clears the safe floors. `GameState.save_room` is set when a save room is entered (in `_place_in` and in `_finish_transition`) and when a machine is used. Entering one also calls `GameState.refill_health()`; `_place_in` skips that for a respawn on the last safe floor (`respawn = true`), so dying in a save room does not refill. The world keeps `SAFE_HISTORY` (8) stretches of floor. Each entry is a room and a position, and a new position within `SAFE_SPACING` (30 px) of the stretch's start updates that entry instead of adding one. A spot is recorded when the player stands on the room's own floor (not an Imprint, not a door block) with no spikes within a cell to either side and no door within two cells (`Room.is_safe_spot`). If the player dies again before standing anywhere new after a respawn, that spot was no good and the newest entry is dropped first.

### Saving (`autoload/game_state.gd`, `autoload/save.gd`)

`GameState` holds what a save holds: `visited` (a set of room ids), `abilities`, `flags` (`pickup:<id>`, `token:<id>`, `save:<id>`), `tokens` carried, `machines` (id → tokens inside), `map_zoom`, `save_room` (an id, or `""`), `health` (full pips, 0 or more) and `max_health` (the bar's length, never below `health`; a save without it gets one as long as its `health`, so no `VERSION` change was needed). `to_dict` and `load_dict` are the only two places that know the shape, and `load_dict` clamps and defaults everything, so a damaged file gives a smaller state and not a crash. `Save.write(room, position)` adds `version`, `room` and `position` (room pixels) and writes `user://save.json`. `Save.load_game()` returns where to put the player, or `{}`. `VERSION` is 3 and `OLDEST` is 2 (`_migrate` carries a version 2 file over: room `1` becomes `s1`, `save:s1_save` is set, the save room is `s1`): a file older than `OLDEST`, newer than `VERSION`, or not valid JSON is renamed `save.json.bad` and the game starts new. `Save.enabled` is independently off in headless runs. `DevSession.isolated()` also guards `write`, `load_game` and `erase` during room/development tests. Ending a test never changes the independent disable flag. A save written before a field existed loads with that field at its starting value, which is why changing a starting number (Imprint's duration) does not reach old saves.

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
0.01–1000000 seconds, and the cooldown 0–1000000 seconds (0 is off), both dev-input
bounds, not gameplay progression limits.
`RESOURCES` covers tokens, health and `max_health` (the bar's length), and coverage tests match the real token cap. A loadout or capture with more pips held than its bar is long gets a bar as long as its pips (`with_loadout`, `GameState.set_loadout`), so a loadout from before `max_health` existed loads unchanged.
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

`Grid.camera_focus` centres a one-screen room, and otherwise clamps the 320×180 world-pixel view inside the room and rounds to whole world pixels. The camera is zoomed by `Display.RENDER_SCALE`, and the door slide steps it onto whole world pixels each tick. `World._process` follows `Player.render_position(fraction)` using `Engine.get_physics_interpolation_fraction()` on each rendered frame, then calls `Camera2D.force_update_scroll`. The player remembers its position before every physics step, including held steps used by save-machine arcs; `place` resets both positions for warps, respawns and retries. With interpolation disabled, the live physics position is used. The camera’s own interpolation and smoothing stay off, so it samples once and remains pixel-aligned. A door slide owns the camera until following resumes.

Previously the camera followed only in `World._physics_process`, before the player stepped. At the 300 px/s fall cap it held still between 5 px updates while the player was interpolated, giving a 5 px oscillation relative to the camera. Render-frame following bounds that mismatch to the half-pixel rounding error. Collision positions, movement timing and the solver are unchanged.

### Imprint in play (`imprint/`)

`ImprintTool` is a `Node2D` child of the world, with interpolation off and drawing in world space. It is active when Imprint is unlocked, the player is in control, a room is current, and the world is not busy.

- **Placing** (`place`, on the `imprint` action): the cell under the cursor is the platform's left end and it is `imprint_width` cells wide. `ImprintRules.check` refuses, in this order, with the reason: outside the room, on solid, on spikes, within a cell of a door's trigger, on a `~` cell, overlapping the player, overlapping a platform that stands. Before that, `ImprintRules.blocked` refuses when `imprint_max_active` platforms stand (`limit`) or `cooldown_left` is above 0 (`cooldown`): a click never replaces a platform. Placing creates `ImprintPlatform.new(rect, duration, not DevSession.classic_imprint_active())`. A placed platform is a rectangle added to the player's collision list by `sync_solids` (the room's rects plus every platform), which is also called when a block goes, when one expires and when a room's doors open.
- **Ageing:** each platform's `age` grows by the physics delta unless the world is busy (a door slide, a death, a 3TM feed). Then `update_footing()` brings its `rect` in line with `age`: each block that went is shattered at its centre and `sync_solids` runs, but the cooldown is not touched. At `lifetime` the last block shatters, `sync_solids` runs, and `cooldown_left` is set to `imprint_cooldown`. `cooldown_left` counts down by the same delta (before the breaks in that tick) and stops with ageing while the world is busy. Leaving a room, dying, warping and a dev-panel Apply of an Imprint setting clear the platforms and the cooldown (`clear`); a retry rebuilds the tool, which starts at 0.
- **The footing and the look** (`ImprintPlatform`): `rect` is always the footing right now (every other reader, the tool, the preview, the tests, uses it) and `full_rect` is what was placed. `blocks_left()` is `ceil(cells × (lifetime − age) / lifetime)`, so one block goes in each equal share of the life. The order is the array `order`, made once in `_init` by the pure static `removal_order(cells, left_x, player_x, facing)`: it repeatedly takes whichever end of what is left has its centre farther from `player_x`, and on an exact tie the end behind the player (the left one when `facing` is 1). `place()` passes the player's centre x and `facing`; with no `player_x` the platform's own centre is used, which gives left, right, middle at width 3. `last_cell()` is the block that lasts. `next_cell()` is `order[cells − blocks_left()]`, `footing(left)` is the run of blocks not yet in the order, and `time_to_next()` follows, `warn_time()` is `min(WARN_TIME, lifetime / cells × 0.5)` (`WARN_TIME` is 0.25 s), and `blinking_off()` is true for every other `BLINK_PERIOD` (0.1 s) in that last stretch before the next block goes. The block that blinks is always an end of the footing, so `drawn_rect()` stays one rect. `draw` paints it white and then a black pixel on every other pixel of the perimeter of that rect shrunk by 1 px; the parity is counted from the placed platform's corner so the dots do not shimmer as it shrinks. `update_footing()` returns the rects of the blocks that just went and never the last one (its going is the platform's expiry). *Classic* (`shrinks == false`, the dev switch) keeps the old dash code: `_line_xs` gives the dashes (one 2 px dash every 4 px, starting 2 px in), `lines_left()` is `ceil(total × (lifetime − age) / lifetime)`, the leftmost goes first, and the last dash blinks (`blink_time()`, `blinked_off()`).
- **The preview:** `_update_preview` recomputes legality only when the key (cursor cell, player cell, on the floor, width, platform count, how many blocks stand across all platforms, whether a cooldown is running) changes. The blocks standing are in the key because a shrinking platform frees cells without the platform count changing. While `ImprintRules.blocked` gives a reason (`limit` or `cooldown`) the state is unavailable wherever the cursor is, so it is the cross. It records unavailable immediately when a rule refuses placement. A legal cell defers the reachable/unreachable distinction to `preview_state()`, which runs `ImprintReach.can_land_on` and caches its result. `ImprintReach` tries input left, none and right, with the jump held for `HOLDS` (3, 8 or 90 ticks) or, from the ground, not jumped; and plans that go straight and steer `STEER_AT` ticks later. A path counts if it lands on the platform's top (within 0.6 px, overlapping it by more than 0.5 px) and does not touch spikes or a door. Its window is `REACH_X` 170, `REACH_UP` 70, `REACH_DOWN` 400 px. Both legal states draw the same dotted outline, so `preview_state()` computes the cached reachable/unreachable distinction only when explicitly requested. Automatic physics/draw updates and clicks never run that diagnostic search.
- **Drawing:** the preview first, then the placed platforms, so a platform is never hidden by the cursor. The operating system's cursor is hidden while the tool is active.

### The solver (`world/reach_graph.gd`, `world/imprint_search.gd`)

The solver answers "can a player get here, and get back", using `MovementSim` and no scene. It is used by `tools/validate.sh` and the tests only.

- **Ledges.** A ledge is a run of standable cells on one row (air, spikes-free, with solid below). `lo` and `hi` are the range a body's centre can have while still on it: a body hangs on until its centre is half a cell past the end, unless a wall or spikes are right there.
- **Edges.** For every ledge, `_ensure_edges` simulates: a jump from the left end, every cell centre and the right end (`start_xs`), with input left, none or right (running only if there are `RUN_UP` = 5 px of ground behind it), and the jump held `HOLDS` = 3, 8 or 90 ticks; and walking off either end. `try_plan` simulates for `limit` ticks (`frame_limit`, 180) against the nearby solids (`near_solids`: ±`REACH_X` 170, up `REACH_UP` 100, down `REACH_DOWN` 400). A path that lands on another ledge is an edge; one that touches a door records a `Touch` (door, position, velocity; two touches within 10 px and 45 px/s are one); one that touches a pickup, token, 3TM or save machine records it, even if it then dies on spikes; one that touches spikes is dead and counts for nothing else. A ledge that runs into a door's trigger walks into it.
- **Doors.** A touch lands where `Door.crossing` puts the body, and `_land` finds what it comes to rest on: standing on something, or falling with input left, none and right for up to `FALL_LIMIT` (300 ticks, so a four-screen drop lands) through the near solids down to the bottom of the room, or through another door, up to `MAX_CHAIN` (3) in a row. Results are cached per touch.
- **Flooding.** `analyze` starts at the start room's spawn and floods along the edges (`_flood`). A room whose exit rule is unmet is **locked**: the door touches of its ledges are held until `_open_locks` finds the rule met by what the run has reached (`ExitRules.met` with flags built from reached things), then released. `_settle` repeats flood, Imprint search and unlock until nothing changes.
- **Air jumps.** While the abilities have `air_jumps` above 0, `_flood` also follows each ledge's air edges (`air_to_ledges`, `air_touches`, `air_pickups`), and `_pickup_reached` counts `air_pickups`. They are worked out the first time a solve needs them, by `_ensure_air_edges`: every ground jump of the ordinary plans with hold `AIR_FIRST_HOLDS` (8 or 90 ticks) gets a second press at each of `AIR_FRAMES` (10, 18, 26, 40 ticks), held `AIR_HOLDS` (8 or 90), and each walk off a ledge a press at `AIR_OFF_FRAMES` (16, 24, 36; earlier ones would still be the coyote jump). `simulate_jump(..., air_jumps, air_frame, air_hold)` runs them. Near a moving platform (many moments) and for a rider (`_ride_air`) fewer frames are tried (`AIR_RIDE_FRAMES`, held 90). Because the edges are kept apart, the rounds before a 3TM gives double jump are unchanged. The cache entry holds them as `air_edges`; `SolverCache.FORMAT` is 2.
- **Breakable walls and the gun.** Walls grow back whenever a room is built, so a wall broken is a state of one visit: the solver keeps, for a room with breakable walls, copies of it with sets of its walls broken (`RoomInfo.solver_variant`; `ReachGraph._variant_for`), named by `RoomInfo.key_for` (the id, then `~` and the broken ids in order), each with its own ledges, edges and cache file (the key is the copy's `id`, which is what the solver keys everything by; `base()` is the room's own id). While the abilities have `gun_unlocked`, `_flood` adds, for a ledge in a room that has breakable walls, `_shot_ledges`: for each column of the ledge and each row from where the body stands up to `_rise_cells` higher (measured with `simulate_jump`, `air` for a double jump) with nothing solid overhead, a shot left or right that reaches a wall that stands before any other solid, an edge to the ledge at the same column in the copy with that wall broken as well. A door always leads into the room as loaded, so a wall never stays broken across rooms. Reports use the room as loaded: a ledge's `describe()`, `reached_rooms`, `needs` and the counts ignore copies, a ledge that only a player who has broken a wall stands on counts as reached, and `_pickup_reached` looks in all of a room's states. A room is capped at `MAX_WALL_STATES` (16) states, and more is an error. Traps are judged on the room as loaded only.
- **Imprint.** With Imprint unlocked, `ImprintSearch.expand(ledge, targets)` adds edges from a ledge by one platform put down from it (see below). The edges are kept in the run (`extra_to`, `extra_touches`, `extra_pickups`) and flooded like any other.
- **Home.** `_home` walks the edges backwards from the start; a reached ledge not in it is a trap. For ledges with no way home with Imprint unlocked, `_place_imprints_to_get_home` searches again with the ledges that are home and the doors as targets. In a `trap: allowed` room a trap is a one-way warning instead.
- **The report** (`Report`): `errors` (a room, door, pickup or exit rule that cannot be reached; a door that lands nowhere; traps), `warnings` (ledges nobody reached, one-way ledges and doors nobody inside can touch), counts, `pickups`, `needs`. Lines are capped at `MAX_LINES` (6) per kind.
- **Progression** (`solve`): solve with the starting abilities; take every pickup, token and 3TM reached; give the abilities those make (`_with`: each pickup's upgrade, and each machine's upgrade if tokens can pay `MACHINE_COST` = 3 for it, machines paid in id order); solve again until nothing new is reached or the abilities stop changing. `taken` only grows, so `_things.size() + 1` analyses are enough for every thing to be discovered one round at a time and for one final pass with the last upgrade applied. Exhausting that safety bound is an error, never a partial successful report. `needs` for a room, ledge or pickup is the set of things taken before the round it first opened, cut down by dropping one at a time (`_needs`). Errors come from the last solve; a trap is judged in the first round it appears, with the fewest abilities.
- **`ImprintSearch`** keeps three caches: `_arcs` (each ledge's jumps, recorded tick by tick), `_legs`, and the graph's `_landings`. `expand` takes the arcs of a ledge (for a moving platform, `_riding_arcs`: the jumps of `ReachGraph._ride`, but from its two ends and middle only and at no more than `RIDING_MOMENTS` (12) of the moments of `phases`, spread over the trip, each arc keeping its start `tick` and the platform it rides, and simulated, and later checked in `_landing`, with `geo.movers`; a landing on a moving platform does not count as landing on the Imprint); wherever a falling arc crosses the top of a cell row, the platforms of `width` cells that arc would land on are **candidates**, if `ImprintRules` allows them and one of the targets is within `REACH_X`/`REACH_UP`/`REACH_DOWN` of standing on them (at most `MAX_CANDIDATES` = 600 per ledge, and `MAX_ARCS_PER_CANDIDATE` = 6 arcs each). Each candidate is checked by re-simulating its arc with the platform in place (`_lands_on`). Whether it is landed on, and on which block, does not depend on what is still out of reach, so it is kept in `_landed` (by ledge, cell, width and time limit) for the rest of the solve: its rounds, and the re-solves `_needs` runs, share it. A candidate that passes gets a **leg**: it is treated as a ledge of its own (`_compute_leg`: about 40 simulated jumps and walks from it) and what it reaches is merged in. The jump onto a platform has `_land_limit` ticks, `clamp(duration × 60 − SPARE_TICKS, 0, frame_limit)` (50 ticks at 1.5 s; at 0 `expand` finds nothing). The legs off it use the ordinary `frame_limit` (180), because the platform is not needed once the player has left it. **The footing the solver counts on is the last block**, which stands for the whole life, so a route it accepts never depends on a block that goes earlier. The player places from the ledge, so `_last_cells(cell, width, arc.start.x)` takes the last of `ImprintPlatform.removal_order` from the arc's start for facing right and for facing left: one block, or two on a tie, and a landing on either counts, because the player can turn before clicking. `_lands_on` records the block it landed on in `candidate.last`, and the leg starts from it. The whole platform still has to be legal to place, and the arc is simulated with the whole platform in place, but it has to land on the last block, and then (`_landing`) the same arc is simulated again with only the last block and has to land in the same place (within 0.5 px); an arc that touches another block differs between the two and is dropped. A leg starts from the last block alone, one block wide, so legs are keyed by cell, width (always 1 now) and limit and are shared across widths.

### The solver's cache (`world/solver_cache.gd`)

`ReachGraph.cache` is empty by default (the tests solve from scratch). `tests/validate.gd` sets it. `SolverCache.entry_for(info)` loads `build/solver-cache/<room id>.json` if its `format`, `solver` and `room` fields match; the entry holds `edges` (every ledge's reach, by index) and `legs` (by `x|y|width|limit`). `_ensure_edges` and `ImprintSearch._leg_of` read an entry before simulating and store what they simulated; `save()` writes the entries that changed. The solver fingerprint hashes `FORMAT` and the text of every file in `SOLVER_FILES`; the room fingerprint hashes the id, position, size, spawn, exit rule, trap flag, the rows (as sealed), the doors (edge, rect, screen, destination, far rect), `~` cells and every thing (type, id, cell, settings). A file that cannot be read, or that does not match, is ignored and rewritten. Not cached, because they are cheap and depend on more than one room: where a door lands a body (`_landings`), and the flood itself. `validate.gd` prints how much came from the cache.

### The map (`ui/map_overlay.gd`, `ui/map_view.gd`)

`MapOverlay` is a `CanvasLayer` (layer 10, process mode always). Holding `map` pauses the tree (it remembers that it did so, and unpauses only when the fade-out ends), fades a dim in over about 0.1 s, and scales a 256×148 panel from 0.92 to 1. The panel holds a 240×132 `SubViewport` texture (`VIEW_SIZE`) with a `MapLayer` in it, a `Marker` and a `Legend` control on top.

- **Map units:** one pixel per cell, a screen being `ROOM_PX` 32×18 and neighbours set `STRIDE` 40×26 apart, so there is an 8×8 gap between rooms. A room of several screens is one rectangle (`room_rect`).
- **Drawing:** visited rooms are outlined (gaps where doors are), the current one filled grey (an opaque grey: a translucent white is premultiplied twice in the web build and vanishes), and connectors drawn to visited neighbours. It redraws, rendering the viewport once (`UPDATE_ONCE`), when the room changes, a room is visited, or the zoom changes.
- **Zoom** (`MapView`, pure statics): `scale_for(level, bounds, view)` is `min(1, view / bounds)` for Out, 1 for Middle, 2 for In; `scaled_rect` scales both corners and rounds them, so lines stay one pixel and neighbours keep their gaps; `view_center(focus, bounds, scale, view)` picks the point at the window's centre (clamped to the visited bounds when the map is bigger than the window, rounded to a pixel). `refresh()` focuses on the visited map (Out), the current room (Middle) or the player (In). `MapLayer` is **moved** to `view/2 − view_center`; a `Camera2D` here only moves in the physics step, after the one frame the viewport renders for a change, so it showed the previous zoom's view.
- **Keys:** while open, `map_zoom_in` and `map_zoom_out` (just pressed) step the level and stop at the ends. `GameState.map_zoom` is the stored level. Closing the map after a change asks the world to save (`save_now`).
- **Legend** (`MapView.legend`): two rows, each an arrow and a magnifying glass drawn from 5- and 7-pixel pictures, on a black patch 1 px from the bottom-right corner. A row that can do nothing is grey.

### The render scale and the world-pixel grid (`core/display.gd`, `core/pixel_art.gd`, `core/pixel_shapes.gd`)

`project.godot` makes the viewport 640×360 (`Display.VIEWPORT`, which `display_test` holds equal to `Grid.SCREEN_SIZE × Display.RENDER_SCALE`), stretched as the viewport by whole numbers with nearest filtering. `World._ready` zooms the camera by `RENDER_SCALE` and sets the window's `oversampling_override` to it, which is what makes text sharp. The UI layers (`Toast`, `DebugOverlay`, `DevPanel`, `MapOverlay`, `Hud`) keep their 320×180 layout and have `scale = RENDER_SCALE`; the map's `SubViewport` is `VIEW_SIZE × RENDER_SCALE` with `size_2d_override` set to `VIEW_SIZE`, and its `TextureRect` ignores the texture's size.

`Display.snapf(x)` is `ceil(x − 0.5)`, the pixel a coordinate lights when a screen pixel is lit if its centre is inside the shape and an edge belongs to the pixel after it. `snap_rect` snaps both corners, so a box that fell between pixels lights the pixels its centres cover, as it did at 320×180. The player body is a `top_level` `PlayerBody` placed each frame at the interpolated position: its corner is `Display.snap`ped and Freddy (`FreddySprites`, rows of the characters in `COLOURS`) is drawn from it as whole pixels, one layer per colour, so nothing is ever between pixels. A moving platform, a dust speck, a shatter burst and a flying token are snapped the same way. Spikes, the token and pickup diamond, the flying token and the 3TM's empty slot are pictures baked from the polygons by `tools/pixel_check.sh --shapes`.

`tools/pixel_check.sh` (not part of `check.sh`, because it needs a renderer) captures scripted scenarios with `--fixed-fps 90`, so frames fall between physics ticks: every room, the player idle, a jump, a run and landing, a death, room 7's lift, a door slide, Imprint (preview, blocked, shrinking, Classic), a shot, the save machine and a 3TM feed. `--baseline` records them as world pixels, the top-left screen pixel of each block (after checking each block is one colour), on a commit whose look you trust: it was first taken at 320×180, and is taken again when the look is meant to change (as for Freddy); the default run draws them at 640×360 with the UI hidden and checks that every 2×2 block is one colour and that the frame, taken at the top-left pixel of each block, equals the baseline. It also saves the UI (toast, F3, the dev panel's tabs, the map at each zoom, the HUD in four states), checks that the text has blocks that are not one colour, and checks that the mouse lands on the right cell. The door-slide frames are compared with the camera rounded in both runs (see the decision log).

### Menus, pause and overlays (`ui/main_menu.gd`, `pause_menu.gd`, `power_popup.gd`, `title_card.gd`, `core/controls.gd`)

**Boot.** The main scene is `MainMenu`. It shows Start Game, or Continue and New Game when `Save.has_game()`, and Controls. A `--room` / `?room=` / `--dev` / `?dev=1` launch swaps straight to the world, so tests, `tools/snap.sh` and dev playtesting boot as before; `?new-game=1` erases the save and then shows the menu. A world the menu starts has `from_menu = true`: it reads no launch arguments and does not reconfigure `DevSession`. `Scenes.swap` replaces the running scene, as `DevSession._replace` does for a dev rebuild.

**The look** is the dev panel's: `UiTheme.build()` (black, 1 px white border, white text) is shared by both. A menu item is a Button with the `MenuItem` variation, whose focused or hovered state is inverted. `MenuList` selects with the mouse (hover), the arrows and W / S (wrapping), and picks with a click, Enter or Space. Every menu layer is a `CanvasLayer` in 320×180 units scaled by `Display.RENDER_SCALE`, and the always-processing ones keep running while the tree is paused.

**Modals.** The pause menu (owner `"pause"`, layer 25) and the power popup (`"power"`, layer 26) use `World.acquire_modal`, so they pause the tree, give way to the map and the dev panel, and release play input only when the keys are let go. Neither opens during an animation (`World.is_busy()`): the pause menu waits and opens when it ends, and the popup waits in `World._popups`. The title card (layer 5) is not a modal and does not process while paused.

**Controls.** `data/controls.json` has one row per control, with the input actions it is drawn from and, for a power, the ability stat it `needs`. `Controls.key_groups` reads the keys from the InputMap, so a rebound key changes the page. The Controls page shows the rows the player owns (the main menu, with no game, shows the base rows); a popup shows the rows an upgrade names in its `controls` list.

**Power popups** come from the `GameState.upgrade_granted` signal, which `grant()` emits for a pickup or a 3TM, and never for dev edits, loadouts or loads (`abilities_changed` fires for all of those). When a popup is coming the toast line is skipped.

**Title cards.** A room entry in `world.json` may have a `title` (`text` and `hold`, the seconds between a 0.3 s fade in and a 0.5 s fade out). `World._maybe_title` shows it once per game and remembers it as the flag `title:<room id>`, which nothing else reads. A room or dev test session shows it once per world and sets no flag. Room 7's `hold` is 2.2 s: `title_card_test` measures the fall from the slide's start to landing as 2.983 s and checks the card lasts 3.0 s. The card is a fixed countdown, so a player who slows the fall (a double jump, an Imprint) sees it end early.

### The HUD (`ui/hud.gd`, `core/pixel_shapes.gd`)

`Hud` is a `CanvasLayer` in the world scene at layer 9: over the room and the title card (5), under the map (10), the toast (15) and the menus, in 320×180 units scaled by `Display.RENDER_SCALE`. A child `Node2D` draws it with `draw_rect` and `PixelArt` pictures (`hud_heart`, the red outline, and `hud_slot`, a slot's inside), on whole UI units. It shows `GameState`'s `tokens`, `max_health` and `health`, less what is still in `flights`: `World._collect` calls `fly_in(kind, world_position)` right after `GameState` has counted the pickup, and the HUD holds that one back until it lands. `to_ui` turns a world point into UI units (`canvas_transform`, divided by the render scale). `_process` moves the shown counts toward the target one step at a time and records each slot's flash or blink in `_effects`; `busy()` is false when nothing is left to do. `sync()` drops flights and effects and shows the state as it is; the world's `_ready` calls it through the HUD's own `_ready`, so a load or a dev rebuild never animates. A dev edit in place (`set_loadout`) animates like play. The layout helpers (`slot_centre`, `pip_rect`, `pip_centre`, `bounds`) are what `hud_test` checks. Empty insides are `Hud.EMPTY` (black); a token fills white and a pip red, inset a unit (`_fill_colour`).

### Effects and small parts

`ExitHalo` is a dithered half-disc of 12 pre-painted 64 px frames, played as a pulse. `Shatter` is 14 square shards that fly out and fall for 0.5 s; nothing fades. `Toast` (layer 15) shows a line for 2.5 s. `Hud` is layer 9. `FlyingToken` arcs 16 px high with a trail of 6 recent positions, every other one drawn. `InventoryMarks` is the rule for the marks, and the picture holds the places: it cuts black 2×1 token lines (up to `GameState.TOKEN_CAP`) at the `tokens` of a `FreddySprites.Frame`, in order, and its `line` once Imprint is unlocked. Every standing picture has the same slots, facing right: row 6 then row 4 on the rear (columns 1–2), then row 5 in the middle (columns 4–5), and a line on row 7 from column 4 to 8. The landing picture has two tokens, rows 8 and 6, and no line. `FreddySprites.rects(pose, index, facing, tokens, imprint)` cuts the marks on the right-facing rows, mirrors the finished rows if he faces left, and returns the layers of rects, one per colour, that `PlayerBody` draws; a mark only shows where the picture is body (`BODY_PIXEL`). `PlayerAnimator` picks the pose and counts `time_in_pose` and `distance_in_pose`, with no node, so `display_test` drives it directly: in the air is the jump, `LAND_TIME` (0.125 s) after `land()` is the landing, a ground speed over `WALK_SPEED` (1 px/s) walks, and anything else stands. `FreddySprites.animation(pose)` is the table of how each pose plays; the walk is 8 pictures, one for each 6 px run. `Player` calls `land()` when the body touches down and `advance()` each rendered frame, and gives `PlayerBody` the pose and `animation(pose).index(time_in_pose, distance_in_pose)`. `FreddySprites.problems()` lists a pose with no animation, an animation with no pictures, and any picture whose rows are not 10 wide, hold a character that is not in `COLOURS` or `EMPTY`, or leave the box; `PlayerBody` pushes them as errors in a debug build and `display_test` fails on them. Drawn pictures are cached by pose, picture, facing, tokens and Imprint, and the body node is moved to its snapped corner each frame, so it is redrawn only when the picture, the facing or the inventory changes. `SaveMachine` draws a pixel ring (outer radius 13 px, the band from 8 px lit a segment at a time) around a hole of 4 px, on a 12 px base, with no antialiasing. `DebugOverlay` (layer 20) shows F3's readout and debug load errors. `DevPanel` (layer 30) owns F2/F4 and the paused playtest UI.

### What the solver and the preview do not model

- **Shooting is tried from a ledge only,** along a straight line to a wall. Shots fired while falling or from a moving platform or an Imprint platform are not tried, nor is breaking a wall the player stands on, nor a shot stopped by anything but solid (a door block, a moving platform, an Imprint platform), nor a wall that takes more than one visit to break. The rows a shot may fly along are the one the body stands in and those it can jump up to with nothing solid overhead, by the simulator's own jump height (single or, with an air jump, double). It can only call something unreachable that is reachable, never the reverse.
- **The air jump** is tried as one extra press, from a ground jump or a walk off a ledge, at a few fixed moments (see `AIR_*` in `ReachGraph`); a second air jump (`air_jumps` above 1), a press with the input changed afterwards, an air jump from an Imprint platform's leg or in an Imprint arc, and one in a fall through a chain of doors are not tried. It is conservative: it can call something unreachable that a double-jumping player reaches.
- Placing a platform in mid-air, and using two in a row. A room that needs either is reported out of reach.
- Landing on a block of a platform that goes before the last one while it stands, or walking off onto such blocks while they stand: only the last block counts. Placing the platform from anywhere but the ledge the jump starts from (the runtime lets the player click from mid-air or after walking; the order is then set from there). Because Classic keeps strictly more footing, validation is conservative for it. The reach preview treats the platform under the cursor as full width (it has not been placed yet), and its look does not tell reachable from unreachable.
- The carry limit of three tokens, and a blocked doorway as a wall for a body falling through a chain of doors.
- Paths other than the fixed plans (the inputs and holds above), so "unreachable" can mean "a plan it did not try". That is why an unreached ledge is a warning and an unreached room, door or pickup is an error.
- A ledge's `MAX_CANDIDATES` cap, and `REACH_*` windows: a platform beyond them is not tried.
- Moving platforms in an Imprint's legs (the jumps off a placed platform pass through them), and a body coming through a door landing on one. A moving platform is only tried at the moments `ReachGraph.phases` picks, so a jump that works only between two of them is not found.

## Decision log

What was decided, in the order it came up, with the reason. Pull requests are named by number.

**The world and the data**
- **Room 7 gets a step, room 9 a floor door, and a third save room.** The jump from room 7's moving platform to exit 1's ledge was too hard, so a small stepped ledge hangs below it. Room 9's floor door drops into s3 over a spike-free strip, and s3's platforms climb back to room 9.
- **One pixel font, a bold capitals cut for titles.** The default sans did not look like the world. Pixel Operator 8 is CC0 and drawn at 8 units, so each of its pixels is a world pixel and it stays sharp at every window size. The title screen and title cards (room 7's) use its bold cut in capitals; `UiTheme.TITLE_FONT` is the single place to give titles a different font later.
- **Fewer toasts, and the dev button is out of the way.** The checkpoint, token-cap, empty-3TM and dev-panel-waiting lines are gone (the world already shows those things). Stat upgrades read "<Name> +1" (a placeholder; the health line was removed once the HUD showed pips). The always-on DEV button and "not saving" label left the play screen: Dev tools is a pause-menu item when dev is available, with the "not saving" note under "Paused".
- **Rooms are ASCII files, ids are numbers, rooms are whole screens.** Easy to write from a drawing, easy to diff, and a room is checked by the same code that plays it. Every rounding made when translating a drawing is reported to the user.
- **`grid_pos` in `world.json`, doors inferred from facing openings.** No hand-written door table to disagree with the map. An opening with nothing beyond it is sealed until a room is placed there.
- **Legend ids are written in the file and never derived.** The save remembers things by id, so a room can be redrawn without losing what the player did.
- **Errors are collected and reported, never thrown.** A bad room should tell its author everything wrong with it at once.

**Movement and the player**
- **The player is a `Node2D` with a box and no physics body; all movement is `MovementSim`.** The solver, the Imprint preview and the player then agree by construction, and `parity_test` enforces it.
- **Fixed 60 Hz physics, engine interpolation on for the player.** The jump does not depend on the display’s refresh rate. The camera samples the player’s interpolated pose per display frame and rounds to a pixel; its own automatic interpolation stays off. Other nodes moved in `_process` are not interpolated, or they would glide from their last position.
- **Doors keep momentum and place** (a body crossing keeps its height or column and its speed, and is pushed in about 20 px); a ceiling door gives a minimum upward speed so a slow player does not stall in the doorway.
- **Death goes back to the last safe floor, not a save point,** with a history of eight stretches so a bad spot costs one extra death and never a loop. An Imprint is never safe floor, because it breaks.

**Tokens, the 3TM, exit rules (PR #16)**
- **Double jump is the first power-up, and Imprint is dev-only for now.** The first 3TM (room 4) gives double jump; Imprint is unlocked only in the dev panel until the user decides where it comes in. The second 3TM (room 9) gives a health pip, a placeholder.
- **Imprint is earned: three tokens at a 3TM.** Tokens are the currency, a 3TM the shop, one upgrade per machine. Partial deposits are saved; a spent machine does nothing; the pocket holds three.
- **A room's exit rule blocks every door, including the one the player came in by,** with solid shaded blocks, not glows. `exits: pickups` is the first rule. A rule is a flag test, so a reload gives the same answer.
- **The body is the inventory** (replaced: see "A HUD shows tokens and health"). Tokens and the Imprint line are cut into the player's body, so no HUD is needed. The facing was a 2 x 2 block in the top corner of the square; Freddy shows it himself (notched front, marks on the rear, mirrored) and the block is gone (the frog PR).

**Freddy the frog**
- **The player is a picture of a frog on the same box.** Redrawn from the user's two sprite sheets; the 10×10 collision box, the movement and the solver are not touched, and a test holds every picture inside the box. A pose is picked from what the body does, and the old squash and stretch is gone, because a picture does not scale.
- **The facing block is gone, and the Imprint line moved from row 8 to row 7 (columns 4–8).** Row 8 is the legs, so a line there would only have cut the two thighs. The frog shows facing by its notched front, and the line stops short of the stack so it never touches a token.
- **The jump picture stays inside the box.** The sheet's jump is about two rows taller than the box. It would draw into a ceiling the body is touching, and tell the player the box is bigger than it is.
- **The third token sits in the middle, not on top of the stack.** On row 2 (the old third slot) its line ran into the rear eye's pupil, which read as part of the eye. The user chose two stacked on the rear (rows 6 and 4) and the third to their right, centred: columns 4–5, row 5, level with the gap. It stays one clear pixel from every other mark and from the Imprint line.

- **A new animation is one table row, and the animator reports time and distance.** The frame count, the rate, the per-pose lookup, the landing's offset and the walk-step maths used to be in five places (an enum value, constants, a `match`, the animator's logic and its timing). Now `PlayerAnimator` only says which pose and for how long and how far (`time_in_pose`, `distance_in_pose`, both from 0 on every change of pose), and `FreddySprites.animation(pose)` turns those into a picture (`every`, `by_distance`, `loop`). `LAND_TIME` and `WALK_SPEED` stay in the animator, because they are how long a state lasts and when it starts, not how its pictures play. The enum `Pose` moved to `PlayerAnimator`, so naming a player state does not depend on one sprite set. The animation's class is `FreddySprites.Clip`, not `Animation`, because the engine has a class of that name that it would shadow. Behaviour did not change: the walk still starts from the first picture after a stand, a jump or a landing.
- **Each picture places its own marks, and the mirroring is done once.** The marks' places were box coordinates in `InventoryMarks` that only worked because every picture shared the same body, and the short landing picture broke that (its third mark fell off the frog). They are now on each `Frame` and `InventoryMarks` is only the rule; the cuts are made facing right and the finished rows mirrored once in `FreddySprites`. The box size (`FreddySprites.SIZE`) is defined once. **Landing shows up to two tokens and no Imprint line** (rows 8 and 6; the user's choice over hiding all marks and over today's behaviour), for the 1/8 s it lasts.
- **The token marks on Freddy are off, with a dev switch.** The user asked to remove the token indication from the sprite and keep it as a dev tool. **The Imprint line is hidden always, with no switch** (the user's choice, after the video showed it joining the gap between his legs so his belly looked cut away; options were hiding it, moving it up to row 6, or leaving it). The marks and the line are still in the pictures and tested (`FreddySprites.rects` takes `tokens`); `PlayerBody.shown_tokens()` passes it 0 unless `DevSession.token_marks_active()`, and `PlayerBody.shown_imprint()` is always false. The token switch is a session switch like Classic Imprint, for a dev test only, so a flag left set cannot show them in a normal game.
- **Freddy has a yellow patch on his front flank.** The user drew it on a screenshot of the standing picture and asked for the sprite to look like that exactly, with the walk and everything else unchanged. Judgements: the drawing's yellow rectangle was a few pixels off the grid (its left edge 4 px short of column 6, its top 3 px above row 4), so it is snapped to columns 6–9 and rows 4–7, which fills the second notch row and leaves the notch on row 3; the drawing's lime was `#D1FA7B` because the capture came from a Display P3 screen (the current lime `#C6FB65` converts to exactly that), so the lime is unchanged and the yellow is stored as the sRGB colour that converts to the drawing's `#F4EC4E`, which is `#F6EC00`; the landing picture was not drawn, so it has the patch on its last two body rows; marks may be cut from the patch as from the lime (`BODY_PIXELS`), so the dormant Imprint line and the token marks behave as before. `display_test` holds the standing picture to the drawing.
- **Freddy is lime, the one thing in the world in colour.** The user chose option 1 ("mono green") of a ten-option colour sheet: lime `#C6FB65` body and legs, white eyes, black pupils and marks (the yellow patch came later, above). It breaks the two-colour rule on purpose, for the player only; geometry, effects and the UI stay black and white (the HUD's red outlines are the one other exception, below).

**Save rooms and health (PR #26)**
- **Dying with no health goes to the save room.** Health is a count of pips, none at the start. With a pip, a death spends it and keeps the old safe-floor respawn. (The pip pickup came later, in room 7; see Health pips below.)
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
- **`trap: allowed`** marks a room that is a dead end on purpose (room 7 and s2, until room 7's way out is built). It turns "no way home" into a warning in that room and relaxes nothing else.
- **The solver follows a fall of any height** (`FALL_LIMIT`), because room 7 is four screens tall.
- **Room 7 is one screen wide.** The screen to its right was empty. The fall stays four screens tall, and the ceiling door stays lined up with room 6.
- **Room 3's entrance lines up with room 2 but cannot reach the token,** and `door_test` checks the level crossing while `reach_test` checks that the staircase is still required, so a later edit cannot restore the old drop or quietly make the climb optional.

**Imprint's look and timing (PRs #18 and #21)**
- **The cursor is always a dotted outline,** whether or not the platform can be reached. A filled cursor with a circling sparkle (and a trailing dotted tail) was built and removed at the user's request. The reach check still runs, so a look that tells them apart can return.
- **A placed platform is drawn over the cursor,** so what can be landed on is never hidden.
- **The dashes are a clock** (since the shrinking Imprint, Classic mode only): four, one going in each equal share of the life, from the left; the last dash blinks (the blink lasts the last dash's share, so it scales with duration and width).
- **A platform lasts 1.5 s** (it was 4, then 3, then 2.5). It was tuned by playing, and the last change was the user's choice together with the lockout below. Saves from before the change keep their old value.

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
- **It moves at a set speed,** `speed=` in pixels a second, and waits at each end, `pause=` (0.2 s, "a split second"). The user first asked for 1.5 s from end to end, then for 60 px/s and then 75 px/s, to try in playtesting. The platform, originally in room 8 and now in room 7, is 5 cells wide, the user's choice over 2 or 3.
- **Leaving it keeps only the player's own velocity.** That was the user's choice for the first version. Without carry-over, a jump from a moving platform never lands back on it if the platform is faster than the player can run (90 px/s). The user had carry-over switched on to playtest it, then off again, so `inherit_platform_velocity` is off in `movement.tres` and the switch stays for trying it again.
- **It is not drawn with a track in the game,** at the user's choice. The renders draw the track.
- **Its clock starts when its room is built,** at the drawn end, waiting, and nothing about it is saved, so it is always in the same place on entering.
- **The row above wherever it goes is kept clear,** and so is a cell around every door. That keeps riding from ever scraping, crushing or killing the player, or carrying them through a door. It is also what lets the solver say that a player on a platform can wait for any moment of its trip.
- **It is never safe floor, and pushing someone into a wall crushes them,** like a death on spikes.
- **The player and the solver share it.** `MovementSim.step` carries and pushes, the solver tries moments spread over its trip, and `platform_test` checks the real player and `simulate_jump` end in the same place with a platform moving.

**Imprint from a moving platform (rooms 7–11)**
- **The solver puts an Imprint down from a moving platform.** The rooms drawn for 7 to 10 place one while riding; before this the solver reported them out of reach. A rider's jumps are tried at the moments `ReachGraph.phases` picks, with the platforms moving, and checked with them moving. Legs stay static: every drawn route ends on a fixed ledge.
- **It keeps the Imprint rule.** Waiting for a platform to break, and for the cooldown, is as possible on a moving platform as on a ledge, because a rider is never scraped, crushed or carried through a door.

**Rooms 7 to 11 (from the user's drawings)**
- **Placement.** Room 8's door to 7 is at its floor, so it sits one screen up from room 7's bottom, and exit 1 is 18 rows above room 7's floor. That fixes rooms 9, 10 and 11 around it. Room 11 has to be two screens wide to meet both room 7 and the top of room 10.
- **Room 7 keeps room 6's drop and s2.** The drawing shows the lower part of the room, compressed. The user chose a wall beside the fall, so a steering faller cannot catch the new ledges, and a step on the landing floor with the platform raised four rows, because the drawn climb (platform, Imprint, exit 1) covers about 13 of the 18 rows.
- **The pip is reached only by the drop from exit 2.** The user asked for it to be too far for a 2-wide Imprint from exit 1 but not for a 3-wide. With shrinking that cannot be built: a 2-wide placed one cell farther puts a block in the same place, and its far block lasts longer (0.75 s against 0.5 s). A probe that lands on every block before it goes found no spot a 3-wide reaches and a 2-wide does not, so the pip sits above what any width reaches from exit 1. This is for the user to revisit.
- **Room 8's floor is spikes** (the user's choice over invisible no-Imprint cells), so an Imprint from the floor cannot skip its platforms. **Room 10's lifts are staggered** and its floor is safe; **its exit shelf runs out from the wall**, because the drawn exit was about 20 columns from lift 3. Room 9's and room 8's shared door is rows 3–5 in both; room 10's door from 9 follows room 9's height.
- **Speeds are first guesses:** 100 px/s in room 8, 60 in rooms 9 and 10.

**Health pips (rooms 7–11)**
- **A pip adds one to the health count, and a death spends it** (changed: see the HUD entry; a death now empties a pip and a save room refills). The user's choice for room 7's pip: no cap, no refill, and nothing shows the count yet besides the line when one is taken. A pip is its own legend kind, `health`, because it changes no ability; it counts for `exits: pickups` like a token, and the solver must reach it like any pickup. Dev tools already set and clear health; a retry puts a taken pip back with the room's flags.

**Wall spikes (rooms 7–11)**
- **Spikes point away from what they sit on.** Room 8 has spikes along its right wall, and upward teeth there read as a stack of floors. Only the drawing turns; the hitbox is still the cell, and the renders still colour the cell.

**Dev map (every room)**
- **Dev mode shows the whole map.** To pick a room to test, the Tab map in dev mode (`DevSession.available`) draws every room, with connectors to all of them, instead of only the visited ones, and writes each room's id in it. A clickable map inside the dev panel was tried and dropped: the panel's window left the map too small. Normal play is unchanged.

**Dev tools (2026-10-24)**
- **Testing is isolated.** The user chose returning to their normal save over permanently granting cheats. F4 now shares that protection.
- **F2, the pause menu, and an explicit export opt-in.** F2, or Dev tools in the pause menu, opens the panel (the old always-on DEV button is gone, so it never covers play; the "not saving" note moved into the pause menu too); `?dev=1` / `--dev` enables exported tools, including the release browser build.
- **Fresh direct launches and reusable named loadouts.** Direct launches reset progression. Loadouts remember only powers and resources, usable in any room.
- **Retry the original test, with the latest explicit tuning.** Cross-room attempts reset progression to their baseline, while duration/width/resource edits remain selected. This avoids replaying the game and avoids silently saving depleted resources as the next loadout.
- **Door bypass and automatic death retry are optional, initially off.** They are separate from real room requirements and ordinary health behavior.
- **Future mechanics must include their dev path.** Registration, setup/removal, retries, loadouts, tests and docs are part of completion, enforced by agent guidance and coverage tests.

**Imprint lockout (PR on `game-tweaks`)**
- **No replacing.** While the limit's worth of platforms stands, a click is refused. Before this, the next click replaced the oldest platform, so a player could keep one alive for ever and walk around any puzzle meant to fit in a platform's life.
- **The starting duration is 1.5 s** (it was 2.5 s). The user's choice. The validator still passes every room at 1.5 s with the same "needs" lines, with `SPARE_TICKS` left at 40.
- **The cooldown is a `min` upgrade kind** (`imprint_cooldown`, lower is better), so a pickup could shorten it later. The panel's rounding of 0.1 steps needed no fix: Godot prints `0.30000000000000004` as `0.3`.
- **A cooldown, `imprint_cooldown`, is an ability stat that defaults to 0.** It starts when a platform breaks on time. The user wanted it adjustable in the dev panel and off in real play until testing says it is fun; 0.2 s is the value to try. Leaving a room, dying and warping clear it.
- **`imprint_max_active` stays** (default 1, still an upgrade). At the limit a click is refused, not a replacement.
- **Old saves keep their stored duration,** so only new games get 1.5 s.
- **The solver needs no lockout model.** It puts one platform down at a time and never two in a row, and none from a moving platform, so waiting is always possible. It does need its time budget changed: the jump onto a platform has to land within its life, and what the player does after leaving it no longer does.

**Imprint shrinks one block per interval (PR #33)**
- **The platform is its own clock.** The dashes counted down a life that was hard to read; a platform that loses a block each interval shows the same thing by being smaller. The dashes no longer mean anything, so a placed platform has a dotted border to tell it from floor and from the cursor.
- **Width 3.** It was chosen so a real middle block lasted. The order now follows the player, and the user kept 3 as the start.
- **The order is set at the click, from the player** (the user's change after playing the first version, which went from the ends toward the middle, left first): the block farthest from the player's centre goes first and the one nearest them last, and it never changes after the click. Measured from the body's centre x; only left and right matter, the blocks being on one row.
- **Ties go by facing:** the block behind the player goes first. A tie happens in real play, because the player respawns on cell centres and the platform snaps to cells. Facing is new: the last left or right input, not part of the movement, not saved, right on a new game, a spawn, a respawn, a warp and a retry, kept through doors and the save machine, and not turned by input the world is holding back. It is shown as a 2 x 2 block cut into the body, one row down, in the top right when facing right and the top left when facing left, clear of the token and Imprint marks. It was first a three-pixel `>`/`<`, then a dot, and the user settled on the 2 x 2 block after trying a one-pixel dot in the corner, a two-pixel dash, and other shapes. The tokens changed with it, from plus shapes to 2 x 2 dots so they sit exactly centred, and then to 2 x 1 lines (the bottom two pixels of each dot, the top line one row lower), which the user found read better.
- **The interval is life / starting width,** not the old dash interval: a block has two dashes' worth of width, so reusing 0.375 s would end a 3-block platform in 1.1 s. At 1.5 s and width 3 a block goes every 0.5 s, and the total time never changes with the width.
- **Only the next block blinks, in its last 0.25 s** (capped at half a share), and its footing stays until it goes. The cap and the border drawn around the blocks that remain while an end block blinks are judgement calls, reported in the pull request.
- **The solver counts only the last block as footing.** It stands for the whole life, so an accepted route does not depend on a block that goes earlier still being there. The last block is the one nearest the jump's start, where the player stands to click; on a tie either counts, because the player can turn first. The cost: a wider starting width never makes a room easier *on paper*, only in play. The second simulation (the arc with the last block alone) is what keeps an arc that brushes an outer block from being accepted. Every room passed with the same "needs" lines as before.
- **Classic stays as a dev comparison switch** (a session switch like door bypass, not saved, not in loadouts, not an ability), so the old look and the new one can be compared until the user has played both.
- **Old saves are left alone:** a save keeps the width it stored. Only new games start at the default.

**Imprint starts 2 wide (rooms 7–11)**
- **The start is 2 blocks, and room 9's 3TM gives the third** (`imprint_width` value 3), the user's choice when drawing rooms 7 to 11. At 1.5 s a block goes every 0.75 s; a tie (the player on the line between the two blocks) goes by facing, which the solver's `_last_cells` already allows for. The solver counts only the last block, so every room validates with the same "needs" lines.
- **Old saves keep the width they stored** (3 for a game started since PR #33). `?new-game=1` or F2 plays at 2.
- **No `Save.VERSION` change.** A missing field falls back to its default.

**Rear token stack**
- **Approved from mockups:** the existing 2 x 1 token lines fill bottom to top behind the facing direction. One pixel separates the stack from the body edge and one row separates each line. For the frog the third moved off the stack into the middle (below). Turning mirrors the stack immediately, and the Imprint line with it (it moved to row 7 for the frog, below).
- **Dev setup uses the existing token control:** F2 can set 0–3 tokens, clear them, retry, and save/reload their count in a named loadout. No new resource or ability is introduced.

**Room 8 merges into the shaft**
- **Room 6’s opening and its whole 7-shaped obstacle move three cells right.** Room 7’s ceiling door moves with them; the shaft stays one screen wide and four tall, and s2 stays on its left.
- **The drop lands safely without a platform catch.** The approved landing was 13 clear cells. A real-player test found that a body crossing the far right of the door at 90 px/s drifts into the first spike after input is released. The spike boundary and platform’s starting endpoint moved one more cell right: 14 clear cells, 16 spike cells, and 11 cells of platform travel. The platform keeps its stable `r8_lift` id, five-cell width, speed 75 and pause 0.2.
- **No new power or progression rule.** Imprint keeps its placement lockout and shrinking last-block footing; the spike section is reached from safe floor using the existing moving platform. F4/room-7 launches start at the bottom `P`; room 6 tests the full fall. Existing dev health, retries, loadouts and save isolation apply.
- **Room 8 is removed from the world.** Normal saves still resume at s1 or s2, and an old visited-room-8 entry is ignored by the map. No save-version change is needed.

**Smooth falling (2026-10-25)**
- **Camera and player use the same presentation time.** At 300 px/s, a physics-only camera jumped 5 pixels per tick while the interpolated player moved between them. Per-frame camera following uses the same previous/current player poses and the same interpolation fraction, then rounds once. The camera test samples 60, 90, 120 and 144 FPS and bounds the offset to half a pixel.
- **The cursor does not search for an invisible answer every tick.** Legal reachable and unreachable positions already share one dotted outline, and placement checks legality rather than reachability. A shaft-fall probe measured the old automatic search at 24.4 ms average / 42.9 ms worst on the user’s machine. Deferring reachability to an explicit `preview_state()` query reduced automatic preview refresh to 0.015 ms average / 0.043 ms worst in the same headless probe. These are diagnostic samples, not a browser FPS guarantee.
- **Imprint’s rules stay the same.** Legality, lifetime, shrinking, lockout and cooldown still run on physics time; no click replaces or refreshes a standing platform. This is presentation and unused-work removal, with no new ability or loadout field. F2, retries and normal-save isolation continue to apply.

**Aiming Imprint without a mouse (2026-10-26, planned, not built)**
- **Placement moves to a fixed set of slots around Freddy, five directions by near and far.** Free mouse aim was hard to use in the split second the puzzles want, and it has no gamepad form. The plan is under "Aiming without a mouse".
- **Both dash-style (hold a direction, J near / K far) and build mode (hold Shift, slowed time, steer, release) are to be built and switched in F2,** alongside free aim as a dev-only third choice, so they can be compared in play. Four schemes were considered. Twin-stick flick was dropped because nothing shows where the platform will go before it is placed. A snapping cursor was dropped because it is still a pointing task and slow on a pad.
- **Near and far are both available from the start; the mouse snaps to the nearest slot.** Decided by the user.
- **A concept video was recorded before any building,** at the user's request. The prototype was throwaway; it is kept with the video in `tools/concept/` for reference.

**Double jump (the first power-up)**
- **One air jump, at the ground jump's speed (`air_jump_speed` = `jump_speed` = 267), and it replaces falling speed.** A full jump rises about 51 px; an air jump at the top rises 51 more, which is what a jump off an Imprint platform put at the top of the first reaches, so the vertical reach the rooms were built for does not change. A separate config value keeps the feel tunable without touching the ground jump.
- **A ground or coyote jump always takes priority.** A press just after walking off a ledge is the normal jump and does not spend the air jump; once coyote time has run out, the same press is the air jump. With none left, a press buffers a ground jump as it always did.
- **`air_jumps` is a count** (`kind: max`, value 1 for double jump), not a flag, so a triple jump is a later `max` upgrade. Landing, spawning, respawning and warping refill it; a door crossing keeps what is left.
- **The solver tries one air press at fixed moments,** not every moment, to keep a cache-less `tools/validate.sh --no-cache` at about 2.5 minutes. Thinner near moving platforms. Misses are conservative.
- **Rooms 5 and 6 are `trap: allowed`** (the user's choice) because crossing room 5's pit with double jump is one-way. Take the mark off when a way back is built.
- **Imprint is dev-only for now, and room 9's 3TM gives a health pip.** Both by the user's instruction, as placeholders. A 3TM takes `upgrade=` (with `value=`) or `prize=health`. Rooms built for Imprint wait for the user's decision before any is changed.

**The gun and breakable walls**
- **The gun is the second power-up, and it shoots only straight ahead.** No aiming: the player jumps to shoot higher. Its rate (one shot every 0.2 s) and speed (260 px/s) are modest, tunable guesses; a later upgrade can raise them.
- **Space shoots, and jump is W or Up.** The user's choice. Space was jump; it moved so a left-hand-on-the-keys player can shoot while holding a direction and jumping on W. The planned Imprint pad table has the same change.
- **Breakable walls are solid and only the gun breaks them.** They look cracked so they read as destructible, and they act as an ordinary platform to stand on.
- **A wall grows back every time the room is built.** The user's choice. Nothing is saved, so a wall gates one visit; the room holds it in a copy of its info (`RoomInfo.variant`), and the loaded room is never changed.
- **A wall takes 3 hits, tunable as "wall strength" in dev tools.** It is a session setting like Classic Imprint and not an ability, because it tunes the world and not the player (see "Dev playtesting").
- **Room 7's pip is closed in by a roof and a tall breakable wall,** not by the short walls first sketched. Walls open on top would let the player drop in with no gun, and no ledge sits level with a short wall to shoot it from. The wall runs floor to roof, and is shot from the exit-2 ledge. After the first playtest the roof moved five rows up and the floor and pip two rows down, so the wall grew taller to meet both; the platform beside the wall was removed so the walls are flush; and the ledge lost its two left cells.
- **Room 9's 3TM gives the gun; a `prize=health` machine is kept** (nothing uses it now).
- **The solver models a broken wall as a state of the room, not progress.** Because walls grow back, copies of a room with walls broken are kept apart and only a door-free shot from a ledge moves between them; leaving always lands in the room as loaded. The pip in room 7 therefore needs the gun (room 9's 3TM and the three tokens before it).

**Resolution (640×360)**
- **2×, keeping game units.** The viewport is 640×360 and the camera zooms 2×; a cell is still 10 world px, and every movement number, room file, save, the solver and every gameplay test is unchanged. Chosen over 3× and 4× because 2× fills 720p, 1080p, 1440p and 4K by whole numbers. Chosen over re-counting positions in screen pixels because that would touch the movement, the solver and the save for no visible gain.
- **The world stays on the old grid.** Everything in the world is snapped to whole world pixels, so the look and the motion are the same as at 320×180. Finer motion or art can be allowed later for one thing at a time (`Display.FINE_GROUP`).
- **Text is the same font and size, drawn at 2×** (`oversampling_override`), so it is sharp, with smooth edges.
- **The built-in whole-number scaling is kept.** A window that showed the 320×180 picture at an odd multiple now drops a step: a maximized browser on a 1080p screen showed 1600×900 and shows 1280×720. Fullscreen 720p, 1080p, 1440p and 4K are unchanged. A scaler of our own, to keep today's size in those windows, was left out for the work and the risk.
- **The map's open and close animation (a panel growing from 92% to 100% over 0.1 s) is drawn finer than before.** The one accepted difference.
- **A door slide steps the camera onto whole world pixels.** At 320×180 a camera between pixels moved the polygon shapes and a player standing at a fractional position by a pixel from frame to frame during the half-second slide. The slide is rounded now, so the picture is steady. The pixel check rounds the camera in both runs for those frames.
- **The engine's own interpolation of the squash is kept.** Superseded by the frog: the squash was a scale and is gone, so there is nothing to interpolate. The body is a picture on a whole-pixel corner.

**Menus, pause and overlays**
- **Continue and New Game when there is a save, Start Game when there is not.** The user's choice, so a player can start over without the URL trick. New Game asks before it erases, with No selected.
- **A launch with `--room` or `--dev` skips the menu.** Tests, `tools/snap.sh` and dev playtesting depend on booting straight in.
- **Esc and P both pause.** The user's choice. A browser can swallow Esc (leaving fullscreen). It costs the palette key, which is unassigned until that is built.
- **Pause menu: Resume, Controls, Main menu.** It reuses the world's modal, so it cannot open over the map or dev panel and waits out an animation.
- **The Controls page shows only the powers the player owns.** The user's choice, so it does not give away what is still to find.
- **A new power pauses the game on a popup until it is dismissed.** The user's choice. It shows once because a pickup or 3TM gives its upgrade once per save.
- **The title card shows once per save, and ends on a fixed countdown.** The user's choices. The countdown is tuned to a straight fall; a player who stalls mid-air sees it end early.
- **The look is the dev panel's, shared.** One theme, `UiTheme`. The theme variation is `MenuItem`: `MenuButton` is a built-in Godot class and cannot be one.
- **The menus' fades are the exception to "nothing fades".** That rule is about the world's picture. The title card fades and the pause menu dims the game behind it, because they are UI over the picture, not part of it.
- **A HUD shows tokens and health, top left, with red outlines.** The user drew it: a heart of three diamond slots for the tokens, and a bar of pips that starts as nothing and grows a square for each pip collected; outlines red, fills black. It replaces "the body is the inventory" and is the second exception to the two-colour rule, after Freddy. The user saw mockups of a white and a black plate behind it and chose neither: no plate, empty slots and pips black inside their red outlines, tokens filled white, full pips filled red. The red fill is inset a unit, because flush red pips merged into one red bar with no borders to count by. The HUD moved from (6, 6) to (14, 14) so it no longer sits on a room's outer wall. Pickups fly into it and count when they land, so the player sees where each one went.
- **Health is a length and a fill, and a save room refills it.** The drawing showed "4 pips, hit once" as three full squares and one outline, so a death empties a pip and the bar keeps its length (`max_health`). The user chose that entering a save room fills every pip; a death with none left goes to the save room, which also fills them. Dying inside a save room does not, since that is not entering it. The "Max Health +1" line is gone: the HUD shows the pip, and `take_health` and a `prize=health` machine return no line.
- **Titles are in `world.json`, not the room files.** A title is presentation; the room file's header reaches the solver and its cache.

**Process**
- **One record.** `AGENTS.md` for how an agent works, `README.md` for the code and its rules, this file for the game and its decisions, `docs/testing-checklist.md` for what nobody has played. `docs/plans/` is history.
- **Every new test is mutation-checked,** and the pull request says which mutants were tried.
- **A pull request is one piece of work, called by its number,** opened on a branch, with the docs in the same change. Merged only when the user says so.

### Guardrails for a change

Do not: draw anything in the world between world pixels (snap it with `Display.snap_rect`, or draw a picture); copy a movement formula; reference an autoload from a pure class; derive or rename an entity id; change the save's shape without `Save.VERSION` and a `_migrate` step; put a `Camera2D` back in the map; add threads to the solver; make the cursor or any effect fade (nothing fades: a pixel is on or off); add colours (the picture is two colours; Freddy's lime and the HUD's red are the only exceptions); call a tuned number the default without saying so in the docs; or leave a test you have not tried to break.

**The Imprint rule every Imprint-related feature must keep.** An Imprint is never replaced, refreshed or extended by another click. No new one goes down until the live one has broken, plus `imprint_cooldown`. A feature that gives the player another way to make footing (more platforms at once, mid-air placement, refreshing a platform's life) or that makes waiting on real floor costly (timers, crumbling floor, chasing hazards) must say how it keeps this rule, in the runtime and in the solver. Routes that moving platforms carry keep it, because a rider can always wait on the platform. Loosening it is the user's decision, not an implementation detail. The footing the solver counts on is the last block, for the whole life: the one nearest where the player stood to place it. A feature that changes the shrink order, the interval, the starting width or how the order is chosen must keep that model true, or change the solver with it.

## Not decided

- How the planned palette pass (`mix(background, foreground, luma)`) treats Freddy. As designed it would turn his lime into a shade of the palette's foreground; keeping him lime means drawing him after the pass or exempting him.
- Whether the gun needs a mark on the body, as Imprint has its line, and whether a shot at 3 x 1 px reads at 1x.
- Per-wall strength (`hits=` in the legend), and walls that stay broken for good.
- Whether Freddy and the token lines read at 1x, (the Imprint line is not shown at all).
- Whether Classic Imprint is removed once the user has played both.
- Whether the shards of each block that goes are too busy.
- What S / Down does.
- How hard a bounce platform throws the player, and whether the player aims it.
- Which aiming scheme ships, dash-style or build mode, and the slot offsets. The plan is under "Aiming without a mouse". It is not built and is waiting on playtesting both.
- How many tokens an upgrade after Imprint should cost, and whether the pocket should ever hold more than three.
- What a spent 3TM should offer, if anything.
- Whether `~` cells should ever be drawn.
- Sound, throughout.
- The title card for room 7, and what its 3TM is for.
- Whether a save from before a change to a starting number (Imprint's duration went from 4 to 2.5 s, and then to 1.5 s) should be brought up to date. Today it keeps the old number, because the save stores the abilities.
- Whether the Imprint cooldown should stay at 0, and if not what value (0.2 s is the one to try in dev tools). To be decided after playtesting.
- A way to start over from inside the game. `--new-game` does it from the command line and the web address.
- How many health pips a player can hold (the HUD's bar wraps after 30, so nothing breaks).
- Whether a death with health should cost anything besides the pip.
- Whether leaving a moving platform should keep its speed (`inherit_platform_velocity`, off now; tried on and turned off again), and room 7's platform's speed (75 px/s), pause and height (row 67, four cells up). All are to be tried in playtesting.
