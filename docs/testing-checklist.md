# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Tried and working

Played in the browser and found good, so these are not listed line by line any more: Imprint in the browser (placing, the preview, the cross, the blink), saving and resuming, the solver and the "needs" lines, movement and doors, the whole world map of PR #17 (rooms 1 to 7, the exit rules, the tokens on the body, the 3TM and its feeding, and the spent machine), and the Imprint look of PR #18 (the dotted cursor, placed platforms drawn over it, the countdown lines, and the blink), and the map zoom of PR #20 (the three levels, the legend, the level kept across reloads, a new game starting fresh, and the marker staying in its room), and the 2.5 second Imprint of PR #21 (the time, the four lines, and the blink on the last line; the duration is now 1.5 s, see "Imprint lockout" below). On 2026-10-22 the release export was also smoke-tested in Chrome: it loaded without console errors, sustained keyboard movement and running jumps worked, and the map opened while held and closed on release. The cloud test executor could not reliably observe and steer a whole platforming route, so that smoke did not replace the earlier full progression playthroughs. A new problem in any of them goes back on this list.

## Room 7 step, room 9 floor door and s3

Nobody has played these yet. `?dev=1&room=7` and `?dev=1&room=9`.

- [ ] **Room 7's step.** From the moving platform, the new stepped ledge under exit 1 makes the jump to the ledge easier.
- [ ] **Room 9's floor door.** The strip beside it has no spikes. Drop through the door into s3, enter its save machine, then climb its platforms back up to room 9.

## Freddy the frog

The new player picture from the user's sprite sheets (the frog PR). Headless tests prove the pictures are whole pixels inside the 10×10 box and that the right one is chosen; whether he looks right and feels right is for a person. `?dev=1&room=s1` (or any room), and F2 to set tokens and Imprint.

- [ ] **His colours.** Lime body and legs, white eyes, black pupils and marks, like option 1 of the colour sheet, in every pose, and the yellow patch on his front flank (columns 6 to 9, rows 4 to 7) as in the user's drawing, in every pose including the landing, mirrored when he faces left. The yellow should read as the drawing's yellow on a Mac screen. Does he read against white platforms and the save machine's lines?
- [ ] **Standing, both ways.** The frog reads as a frog at 1x: eyes, notched front, two feet. Turning mirrors him at once.
- [ ] **The walk.** Eight pictures at 6 px each: does it read as walking, not shimmering, at full speed and while speeding up and slowing? It starts from the first picture each time he stops.
- [ ] **The jump and the landing.** Legs thrown wide for the whole time he is in the air (including a fall off a ledge and an air jump), then the low picture for about an eighth of a second. Nothing draws outside the box.
- [ ] **No token marks in normal play.** Carry 1 to 3 tokens in a normal game (and in `?dev=1`): the body shows no marks for them, and no Imprint line either, with or without Imprint (his belly is solid down to the gap between his legs). In F2, Player tab, "Show token marks on Freddy" turns them on at once and off again; it survives a retry, and End playtest turns it off.
- [ ] **Token marks on him (switched on in F2).** 0 to 3 tokens, with and without Imprint, both ways. Two stack on the rear; the third sits in the middle of the body, level with the gap between them, and reads as a token, not part of the eye.
- [ ] **Landing with tokens.** With 3 tokens and the marks switched on, the low landing picture shows at most two token lines (the bottom one just above the rear foot), for about an eighth of a second, and the marks are back on the standing picture. Facing either way.
- [ ] **Nothing else changed.** He lands on and walks off the same edges, fits the same gaps and shatters on spikes as before.

## Room 11

The new room from the user's drawings. Start `?dev=1&room=11`, and in F2 turn the gun on and set Air jumps to 1 (or play from room 10).

- [ ] **The stairs** from room 10's door down to the floor read as steps, and climb back up.
- [ ] **`r11_lift`** rises to one cell under the ceiling spikes: does it feel fair, and is jumping off it at the top as dangerous as intended?
- [ ] **`r11_slider`** over the floor spikes: its timing at 60 px/s, and getting on and off it.
- [ ] **The pillar lift** above the pillar's top spikes: getting onto it from the slider, and its top, one column from the ceiling spikes.
- [ ] **The door wall.** Shoot the L by the left door (three hits) and walk out into room 7's exit 2.
- [ ] **Without the gun.** From room 10's bottom left platform a double jump reaches the door back to room 9 (the user found this in play), so room 10's token gets back to room 9's 3TM.

## Gun and breakable walls

Nobody has played these yet. Headless tests prove the rules, not the feel. Use `?dev=1&room=7`, open F2, turn the gun on and Apply (add Air jumps 1 if you want to climb), or play to room 9's 3TM, which gives it.

- [ ] **The rate.** Mash Space: about three shots a second, and no faster. Is it spammable enough, or too much? Tuning knobs: Gun cooldown and Shot speed in F2 (the starting values are in `Abilities`).
- [ ] **The shot reads.** A 3 x 1 world px white line: can you see it, and does it feel quick? Does it feel right leaving the body in the direction faced, and after turning mid-air?
- [ ] **Shooting while jumping.** Jump and shoot to hit something higher. A shot stops at walls, moving platforms and Imprint platforms, and goes on past spikes.
- [ ] **Space shoots, W and Up jump.** Space no longer jumps. Is it comfortable with a direction held?
- [ ] **The cracks.** A wall looks cracked and breakable from across a room. Each hit flashes it and adds cracks, and the third shatters it cell by cell.
- [ ] **Standing on a wall.** An intact wall holds the player like any platform; once it breaks, they fall.
- [ ] **A wall grows back.** Leave room 7 and come back, die and respawn in it, and retry from F2: the wall is whole each time.
- [ ] **Room 7's pip.** Come in from room 11 (`?dev=1&room=11`), stand on the exit-2 ledge (the left two cells were removed), face left and shoot the wall (three hits), then jump in for the pip. The roof is five rows higher than before, with the wall running floor to roof and the floor two rows lower than the original, flush with it. Walking off the ledge now drops past the box. The player cannot get in without the gun, by jumping or dropping.
- [ ] **Room 9's 3TM** gives the gun with "Gun. Space shoots the way you face." (`?dev=1&room=9` with three tokens set in F2).
- [ ] **F2.** Gun on/off, cooldown and speed apply and survive a retry and a named loadout. Wall strength (Player tab, below Classic Imprint): 1 breaks in one shot, 5 in five, takes effect at once, survives a retry, and End playtest resets it to 3.
- [ ] **The solver agrees.** `tools/validate.sh` lists room 7's pip as needing the gun (via room 9's 3TM and its tokens) and passes. Nobody has played the whole route to the pip without dev tools.
- [ ] **Nothing odd:** shooting during a door slide, the map, the F2 panel or a save does nothing, and shots do not follow you into the next room.

## Double jump

Nobody has played this yet. Headless tests prove the rule (height, refill, priority), not the feel. Start `?dev=1&room=s1`, open F2, set Air jumps to 1 and Apply. Or play from a new game: the 3TM in room 4 gives it.

- [ ] **The feel at the top of a jump.** Hold jump, then press again near the apex: a second jump of the same size that rises about 10 cells in all. Does it feel natural, or floaty/snappy? Tuning knob: `air_jump_speed` in `movement.tres`.
- [ ] **Late in a fall.** Press jump well into a fall: it should still jump at once, from the falling speed.
- [ ] **Tap versus hold on the second jump.** Releasing early gives a short second hop.
- [ ] **A third press does nothing**, and a press just before landing still gives a jump on landing.
- [ ] **Refill.** Land on a floor, on a moving platform (room 7, 8, 10) and, with Imprint on in F2, on an Imprint platform: the air jump comes back each time. Spawning, respawning and warping also refill; crossing a door keeps what is left.
- [ ] **Walking off a ledge.** A press right after leaving is a normal jump and keeps the air jump; a press after a moment is the air jump.
- [ ] **Feedback.** The jump picture (legs thrown wide) from take-off to touch-down, the low landing picture for about an eighth of a second, and a puff of dust downward from the feet on an air jump.
- [ ] **F2 field.** Air jumps 0, 1 and 3, Apply, retry and a named loadout round trip. Lowering it mid-air takes the extra jumps away at once. Changing it does not clear placed Imprints.
- [ ] **Room 4's 3TM** gives double jump with the line "Double jump. Press jump again in the air.", and Imprint stays locked (no cursor platform).
- [ ] **Room 9's 3TM** (reached with `?dev=1&room=9` and three tokens set in F2) now gives the gun; see "Gun and breakable walls". No room gives a health pip from a 3TM any more.
- [ ] **Rooms 5 and 6 without Imprint.** Cross room 5's pit with double jump from the token platform (the left floor is a one-way landing, so you cannot cross back; both rooms are `trap: allowed`). Then try the rest of the world to room 10 and the 3TM in room 9 without Imprint: the validator says all 56 ledges are reachable, but nobody has played it.

## Fall presentation

The user confirmed the merged room 7 layout and the subsequent falling-performance fixes work in their browser playtest on 2026-10-25. The broader comparisons and edge cases below have not been individually confirmed.

- [ ] **The long fall with Imprint on and off.** Start `?dev=1&room=6`, enable Imprint to cross the wall, and release movement in the drop. The body stays steady while the room scrolls; moving the mouse does not hitch the fall. Compare on a high-refresh display if available.
- [ ] **Pause, retry and room changes.** Open/close F2 or the map during the fall, retry, die and respawn, and cross into s2. No camera sweep from an old position or drift during pause.
- [ ] **Cursor and placement.** Legal positions still show the dotted outline, blocked positions the cross; clicking while an Imprint stands does not replace it or restart its life. Try cooldown and shrinking in F2.

## Imprint lockout

Nobody has played these yet. Headless tests prove the rule, not the feel. Use `?room=5` after the 3TM, or `?dev=1&room=5` with Imprint turned on in F2 (room 4's 3TM now gives double jump, not Imprint).

- [ ] **Clicking again and again.** While a platform stands, more clicks do nothing: it is not renewed and its clock does not restart.
- [ ] **The cross while locked out.** The cursor is the small × anywhere while a platform stands, and the dotted outline comes back once it has broken.
- [ ] **1.5 s is enough.** Room 5's pit both ways, and room 6's wall. The validator passes, but check the jump onto a platform and off it is not too tight in real play.
- [ ] **The clock at 1.5 s (Classic only).** The four dashes (one every 0.375 s) and the last-dash blink still read. Since the shrinking Imprint this is only in F2 with Classic Imprint on.
- [ ] **The cooldown at 0.2 s.** In F2 set the cooldown to 0.2 and Apply: after each break the × stays for about a fifth of a second. Does it feel fair, or should it stay at 0 (the default)? Also try 0.5.
- [ ] **Leaving a room or dying** with a cooldown running: the next room starts with no cooldown.

## Rooms 7 to 11

Start `?dev=1&room=6` with Imprint on in F2 (or later rooms directly with `room=<id>`).

- [ ] **Room 7's fall.** Steering hard right through room 6's hole: the wall keeps you on the left, and you land on the floor or the step, never in the first spike.
- [ ] **Room 7's climb.** Step, platform, then an Imprint while riding, to exit 1. Is the Imprint-from-the-platform jump fair?
- [ ] **Room 8 at 100 px/s.** Tricky but fair; the upper platform to the exit ledge needs the Imprint.
- [ ] **Room 9.** The lift, the Imprint across to the 3TM pillar, the Imprint up to the exit and the token.
- [ ] **Room 10's lifts.** Lift 1, 2, 3 timing at 60 px/s, then the Imprint to the shelf.
- [ ] **The loop.** 10 → 11 → 7's exit 2 → drop to the pip → exit 1 → 8 → 9, and feed the third token: the gun (and not Imprint 3 wide, as it was).

## Health pips

- [ ] **Room 7's pip.** Reached by dropping from exit 2, then shooting the wall that closes it in (see "Gun and breakable walls"). It reads as a plus that bobs, apart from tokens and pickups; taking it shows no line of text and it flies to the HUD, where the bar grows its first square. Then die on spikes: you come back on the last safe floor, not at s2, the square empties, and the next death goes to s2, which fills it again. In F2, set health and max pips, use +1 pip, Refill, Empty pips and Clear health, retry (the pip comes back), and round-trip it through a loadout.

## The HUD

Nobody has played this yet. `?dev=1&room=2` (a token) or `?dev=1&room=7` (the pip; use F2 to give the gun), F2 to set tokens and pips.

- [ ] **It stays put.** Top left, over every room, during door slides, deaths, a save, a 3TM feed and a title card; under the map, the pause menu and the dev panel. It reads over black space, and does not sit on a room's outer wall.
- [ ] **Tokens.** Taking one sends it flying from where it was to the heart: left lobe, right lobe, then the point. The slot flashes red and fills white as it lands, and the heart jumps a pixel. With three, the next token stays in the room and nothing flies. Feeding a 3TM empties the slots from the point back, a blink each.
- [ ] **Pips.** The first pip adds a square at the heart's tip; each next one grows the bar a square, then flashes white and fills red, and full pips are still told apart. A death empties the rightmost full pip with a blink; entering a save room (s1, s2, s3) fills the empty ones left to right. Dying inside a save room does not.
- [ ] **Nothing fades and nothing is between pixels**, at 1280×720 and fullscreen. The flight is quick and reads as going *into* the HUD.
- [ ] **A reload, a retry or End playtest** shows the right counts at once with nothing flying.

## Imprint shrinking

Nobody has played these yet. Headless tests prove the order, the timing and the solver, not the feel. Use `?dev=1&room=5` with Imprint turned on in F2 (or `?room=5` after the 3TM).

- [ ] **Rooms 5 and 6 with a 2-wide shrinking platform** (the new start; use `?new-game=1` or F2, since an old save keeps 3). Room 5's pit both ways and room 6's wall can be crossed. A block goes every 0.75 s, the one farthest from where you clicked first, and the one nearest you lasts to the end.
- [ ] **The blink warning.** The next block blinks in its last quarter second and the footing under you does not change while it does. It reads, and it is not annoying.
- [ ] **The dotted border.** A placed platform is a white block with a black dotted inner border, and it looks different from the white dotted cursor outline.
- [ ] **Per-block shards.** A shatter at every block going is not too busy.
- [ ] **The order follows where you stood.** Click from the left of a platform: it shrinks toward the left. From the right: toward the right. Standing right under its middle, the block you face lasts. Moving after the click changes nothing.
- [ ] **Freddy, the facing and the token lines.** The frog's notched front is the way you last went (right, left) and it mirrors at once; tokens as 2 x 1 lines, two stacked bottom to top opposite facing (one pixel inside the edge, one clear row apart) and the third in the middle beside them; all read at a glance and none clash (with "Show token marks on Freddy" on in F2; they are off otherwise). Check with 0 to 3 tokens (the Imprint line is never drawn). A respawn or warp faces right. Use F2 to set 0–3 tokens and remove them; turn both ways, retry, and round-trip the count through a named loadout.
- [ ] **Landing on a block that goes early feels fair.** The solver only counts the last block; in play the others help. Landing on one that is about to go should not feel like a trap.
- [ ] **Classic switches cleanly both ways.** In F2, Player tab: Classic on gives full-width platforms with dashes, off gives shrinking, and toggling clears the platforms. The pause menu's dev line says "classic imprint". End playtest turns it off.
- [ ] **Widths 1, 2 and 5 in F2.** Width 1 never shrinks; widths 2 and 5 keep the block nearest where you clicked from. The total time stays 1.5 s.

## Save rooms

Nobody has played these yet. Use `tools/build_web.sh`, `tools/serve.sh` and `?new-game=1` for the first.

- [ ] **Room s1 on a new game.** The door in the right wall is blocked and the machine stands open, a split sphere on the middle platform. Jump up to the platform: as soon as you are in front of it you hop into the middle, it closes and spins, a "Game saved" line shows, the blocks shatter, and you are popped out on the far side, in about 1.2 s. Check the hop, the spin and the pop read well, the time feels right, and the close horizontal lines read as a shaded ball and not like a door's halo.
- [ ] **Entering from the other side.** Leave by the door, come back in, and enter the zone from the right end of the platform: you pop out on the left.
- [ ] **Once per visit.** After a save, walking back and forth in front of the machine does nothing, and the sphere stays closed. Leave s1 and come back: it is open again and works once more.
- [ ] **Dying in room 5.** With no pips you come back in s1 inside the closed sphere, which spins as it does for a save, then opens and pops you out to the right, with no "Game saved" and the door open. The whole route to room 5 is walked again.
- [ ] **Reload** (a plain reload, not `?new-game=1`) after getting as far as room 5 or past the 3TM: you start inside the machine in s1 (it opens and pops you out to the right) with Imprint and the tokens you had, and rooms you took things in still have them gone.
- [ ] **An old save.** If you have a save from before this change, a plain reload carries it over: you start in s1 with the door open.
- [ ] **F4, `s`, `1`, Enter** warps to s1 when dev tools are available, and `?room=s1` starts there with the door blocked.

## Moving platforms

Nobody has played these yet. `?room=7` starts on room 7’s safe landing beside the platform (with no Imprint and no tokens; neither is needed here).

- [ ] **Getting on.** From the clear floor inside the door, jump onto the platform while it waits at the left. The platform's top is four cells above the floor, a full jump. Check the 0.2 s wait reads as a wait, and whether the jump is too easy or too hard (row 66, one cell higher, is as high as a full jump reaches).
- [ ] **Riding.** Stand still and ride it out to the wall and back. At 75 px/s each way takes about 1.47 s. Check it looks smooth (it moves on physics time, with interpolation), and that the player sits still on it and does not jitter or slide.
- [ ] **Walking on it** while it moves, both ways.
- [ ] **Jumping off it while it moves.** `inherit_platform_velocity` is off, so a jump or a step off the end keeps only your own speed: a jump straight up goes straight up and the platform goes on without you. Is it easy to land back on it, and to hop between the strip and the platform? Set it to true in `src/player/movement.tres` to compare (it was tried on and turned off).
- [ ] **Getting off.** Step off its left end onto the clear floor as it gets back. With a 0.2 s wait this needs you to be at its left end when it arrives. Too tight? Try a longer `pause=` in `data/rooms/7.txt`.
- [ ] **Its speed.** Try other `speed=` values in `data/rooms/7.txt` (it is 75 px/s now; the user first asked for a 1.5 s trip, 133 px/s).
- [ ] **Dying.** Fall off into the spikes: with no health you go back to your save room (s2 if you saved there). Coming back, the platform has started over, waiting at the left.

## Respawn

The safe-floor respawns below happen when the player has health. Use `?dev=1`, grant health in F2, and leave retry-on-death off to try these now, before a health pickup exists. `hazard_test` also covers them.

- [ ] **Dying right after a door.** The respawn spot may be in the previous room. Check that it feels right, and that you do not die twice.
- [ ] **A respawn that is not safe.** Make one by standing on an Imprint over spikes and then dying; you were shown this fixed. Also try standing half on a ledge and half on an Imprint.
- [ ] **Falling out of a room** through a hole in the floor that leads nowhere.
- [ ] **The step-back.** If you can make two deaths in a row, check that you end up on real floor and not in a loop.
- [ ] **Dying in a locked room** (room 2, before the token). You come back inside room 2, not in room 1.

## Resolution (640×360)

Not yet played by a person. `tools/pixel_check.sh` passes (the world is on the grid and equal to the 320×180 baseline), so these are about how it feels.

- [ ] **It looks the same.** At the default 1280×720 and fullscreen, the world is the same blocky picture it was: walls, the player, spikes, tokens, the save machine, halos. Nothing is smoother or thinner.
- [ ] **It moves the same.** Jump, land, run, ride room 7's lift, cross a door: the same stepping, with no shimmer in the player or the walls. Compare a door slide: it is steadier than before, which is intended.
- [ ] **The text is sharp.** The toast ("Game saved"), F3, the F2 panel on each tab, and the map's room ids (in dev mode) are crisp pixel text in Pixel Operator 8, hard-edged with no blur at any window size, and nothing is clipped or overlapping.
- [ ] **The map.** Open and close it: the panel grows a little finer than before, and that is expected. Zoom through all three levels.
- [ ] **Imprint aims where the mouse is.** The cursor platform and the placed platform land on the cell under the pointer, at 1280×720 and fullscreen.
- [ ] **Window fit.** A maximized browser window on a 1080p screen shows the game at 1280×720 with wider borders, and not at 1600×900 as before. Fullscreen fills the screen. Say if a window size you use now feels too small.
- [ ] **Frame rate.** F3 stays at 60 FPS in the browser, including fullscreen on a large screen.

## Dev playtesting

Automated catalog/session/UI tests pass only after the full check gate. A native
panel render is a layout check, not a completed human browser playthrough.

- [ ] **Activation.** `?dev=1&room=7` in the release browser build and `--dev --room=7` natively; F2 and the pause menu's Dev tools item open/close, Escape cancels, F4 finds ordinary and save rooms. Without `dev=1`, release tools stay unavailable.
- [ ] **Save isolation.** Start with a known normal save, cheat, collect, feed a 3TM, use a save machine, warp, die and retry. End playtest/reload normally: the original save remains. Test `dev=1&new-game=1` without losing it.
- [ ] **Powers.** Tokens add/fill/empty; health pips and max pips (+1 pip, Refill, Empty pips, Clear health), shown in the HUD at once; Imprint on/off, width, duration and active count up/down. Invalid fields do not partly apply. Bounce is explicitly unavailable.
- [ ] **The Tab map in dev mode.** Hold Tab: every room is drawn (all 12, with doors joined) with its id written in it, legible at each zoom level and over the grey current room, at all three zoom levels, even in a fresh test. Without dev tools (a release build with no `dev=1`), only visited rooms show.
- [ ] **Input and pause.** Edit while a platform moves or an Imprint ages: both stop. Close while holding movement/jump or clicking: no unintended input. Map and panel do not unpause each other. F2 during a save/3TM/door animation waits, and a second F2 cancels.
- [ ] **Retries.** Start in one room, collect/spend things and walk elsewhere, then retry: original room/progression return, tuned powers persist, health/tokens refill, moving platforms restart. Try with retry-on-death both on and off.
- [ ] **Door bypass.** Locked rooms 2 and s1 open without taking/saving. Switch off away from the doorway: requirements return. Switch off in the doorway: it refuses. No opening appears through a sealed wall.
- [ ] **Loadouts.** Create/update/select/rename/delete. Select stages values until Apply. Reload the browser: saved names persist separately from progression. Reuse one loadout in different rooms.
- [ ] **End playtest.** Normal save resumes at its usual save room; no-save case starts normally. Refreshing a URL still containing `dev=1` starts another fresh test.

## Debug tools

- [ ] **F4, a room number, Enter** in the protected room picker, in a real window. Digits, Escape, a room that does not exist.
- [ ] **A load-error overlay.** In a debug build, break a room file on purpose (a bad `exits:` line is a good one) and see the errors appear on screen. Never seen outside of tests.
- [ ] **`godot --path . -- --room=3`** on the desktop build. A room started this way uses no save, so tokens and the 3TM start empty.

## Rooms from drawings

- [ ] **The whole drawing-to-room routine on a real drawing.** Nobody has run the protocol in `AGENTS.md` on a real photo. Expect to change the instructions after the first try: how a drawing is read, how rounding is reported, what the key should look like.
- [ ] **A drawing with a token, a 3TM, a hazard and a locked room in it,** to try the legend lines and the cheat-sheet. The key for a 3TM and for "doors blocked until the pickups are taken" is new.
- [ ] **A room of two or more screens** and a room with a door that spans a screen boundary, drawn by hand.

## The solver

- [ ] **A room that the validator calls shut but that a person can open.** The search leaves out placing a platform in mid-air and using two in a row. If you find a way across with either, we know which one to add. Room 5's pit is the best place to try: it might be crossable from the floor with two platforms in a row.
- [ ] **A room that the validator opens but a person cannot.** The search ignores the limit of three tokens, and does not treat a blocked doorway as a wall for a body falling through a chain of doors.
- [ ] **A `~` cell in a real room.** None of the rooms use one. Try it on the pit in room 5 or the wall in room 6 to see the solver shut the room again and the cross appear in the game.
- [ ] **Validator time.** On 2026-10-22, `tools/validate.sh --no-cache` took 13.5 seconds for 7 rooms and a warm cached run took 1.5 seconds. Before the room merge, with 9 rooms and room 8's moving platform it took about 32 seconds cold and 8 warm (main was already at 28 and 8 before the platform). It keeps what it works out about each room in `build/solver-cache/`. Check the numbers again as the world grows. Edit one room and run it again: only that room should be redone (the `cache:` line says how many). If an answer ever looks stale, `tools/validate.sh --no-cache` or deleting `build/solver-cache` gives the answer from scratch.

## Movement and doors

- [ ] **Room 2 to room 3.** Cross both ways at different speeds. The floors and two-cell openings line up with no drop, and room 3's entrance still cannot skip the staircase to its token.
- [ ] **Room 7's shaft.** It is one screen wide and four tall. The opening and 7-shaped obstacle in room 6 are three cells farther right. Release movement during the fall: land on the clear left floor, then walk left into s2. Check the right-hand spikes and moving platform are in this same room, and the map has no separate room 8. Try `?dev=1&room=6` with Imprint enabled, then retry the fall.
- [ ] **The up-boost** of 180 px/s at ceiling doors: helps, or feels like a jump pad. The validator would still pass with a much weaker boost, because it only checks that some entry through the door lands.
- [ ] **Doors that are not level,** and a door with a wall right behind it.
- [ ] **Every way into a door,** not only the one the validator tried: slow, fast, from above, from the side.

## Menus, pause, popups and title cards

Nobody has played these. Headless tests prove the logic, not how they look or feel. Use `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060 (and the published site after the merge).

- [ ] **The main menu.** It shows first, with "Freddy's Fall" and the items. Mouse hover selects (inverted box) and a click picks. Up / Down / W / S move and wrap, Enter and Space pick.
- [ ] **Start Game, Continue, New Game.** With no save: Start Game and Controls. With a save: Continue (resumes at the last save machine), New Game (asks first, No is selected, Esc answers No; Yes starts over) and Controls.
- [ ] **`?new-game=1`** erases the save and shows the menu with Start Game. `?room=7` and `?dev=1&room=4` skip the menu.
- [ ] **Controls and Back.** The page lists Move, Jump, Map, Map zoom and Pause as key pictures with what they do (arrows drawn as arrows). Does it read well at 1280×720 and fullscreen?
- [ ] **Pause.** Esc and P open the pause menu and close it; the game is frozen and dimmed behind it. Resume, then Space and a click do not shoot or place Imprint. During a door slide or a death the pause waits for it to end. It does not open over the map or the F2 panel.
- [ ] **Pause, Controls.** The same page, plus a row for each power you own (double jump after room 4's 3TM, Shoot after room 9's). Esc or P goes back to the pause list.
- [ ] **Pause, Main menu** then Continue: back at the last save machine with everything still collected.
- [ ] **The power popups.** Room 4's 3TM (double jump) and room 9's 3TM (gun) pause the game on "NEW POWER" with the key picture. Enter, Space, a click, W or Esc dismisses it after a moment, and play resumes. F2 edits show no popup.
- [ ] **The room 7 title card.** The first drop from room 6 shows "Freddy's Fall" as the slide starts and it is gone about as Freddy lands. It does not show again after a reload or a second drop. A new game shows it again. Does the timing feel right, including after a double jump?

## Published site

- [ ] **After the first deploy and after any change to the deploy workflow,** open https://kvelury.github.io/freddysfall/ on your own machine. The game loads, a door takes you to the next room, a reload keeps the save, and `?new-game=1` starts over.
- [ ] **A first visit on a fresh browser profile** loads in a reasonable time (the `.wasm` and `.pck` are about 10 to 15 MB compressed) and plays audio after the first click.

## Things that were never built, so there is nothing to test yet

Room 7's title card and its 3TM, gamepad and keyboard aiming, touch input, sound, the softer palettes, L-shaped rooms, the map panning, a second kind of token or a bigger pocket, and authored pickups/machines for Imprint numeric upgrades, plus bouncing. Width, duration, the cooldown and multiple active platforms already work and can be set through dev tools. Width and duration are read when a platform is placed, but no room gives either upgrade now (the width pickup went with the old room 5), so Imprint is the only upgrade you can get today.
