# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Tried and working

Played in the browser and found good, so these are not listed line by line any more: Imprint in the browser (placing, the preview, the cross, the blink), saving and resuming, the solver and the "needs" lines, movement and doors, the whole world map of PR #17 (rooms 1 to 7, the exit rules, the tokens on the body, the 3TM and its feeding, and the spent machine), and the Imprint look of PR #18 (the dotted cursor, placed platforms drawn over it, the countdown lines, and the blink), and the map zoom of PR #20 (the three levels, the legend, the level kept across reloads, a new game starting fresh, and the marker staying in its room), and the 2.5 second Imprint of PR #21 (the time, the four lines, and the blink on the last line). On 2026-10-22 the release export was also smoke-tested in Chrome: it loaded without console errors, sustained keyboard movement and running jumps worked, and the map opened while held and closed on release. The cloud test executor could not reliably observe and steer a whole platforming route, so that smoke did not replace the earlier full progression playthroughs. A new problem in any of them goes back on this list.

## Respawn

- [ ] **Dying right after a door.** The respawn spot may be in the previous room. Check that it feels right, and that you do not die twice.
- [ ] **A respawn that is not safe.** Make one by standing on an Imprint over spikes and then dying; you were shown this fixed. Also try standing half on a ledge and half on an Imprint.
- [ ] **Falling out of a room** through a hole in the floor that leads nowhere.
- [ ] **The step-back.** If you can make two deaths in a row, check that you end up on real floor and not in a loop.
- [ ] **Dying in a locked room** (room 2, before the token). You come back inside room 2, not in room 1.

## Debug tools

- [ ] **F4, a room number, Enter** in a debug build, in a real window. Digits, Escape, a room that does not exist.
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
- [ ] **Validator time.** On 2026-10-22, `tools/validate.sh --no-cache` took 13.5 seconds for 7 rooms and a warm cached run took 1.5 seconds. It keeps what it works out about each room in `build/solver-cache/`. Check the numbers again as the world grows. Edit one room and run it again: only that room should be redone (the `cache:` line says how many). If an answer ever looks stale, `tools/validate.sh --no-cache` or deleting `build/solver-cache` gives the answer from scratch.

## Movement and doors

- [ ] **Room 2 to room 3.** Cross both ways at different speeds. The floors and two-cell openings line up with no drop, and room 3's entrance still cannot skip the staircase to its token.
- [ ] **Room 7's shaft.** It is one screen wide and four tall. Falling in from room 6 lands on the floor, and the map shows one column under room 6.
- [ ] **The up-boost** of 180 px/s at ceiling doors: helps, or feels like a jump pad. The validator would still pass with a much weaker boost, because it only checks that some entry through the door lands.
- [ ] **Doors that are not level,** and a door with a wall right behind it.
- [ ] **Every way into a door,** not only the one the validator tried: slow, fast, from above, from the side.

## Things that were never built, so there is nothing to test yet

Room 7's title card and its 3TM, gamepad and keyboard aiming, touch input, sound, the softer palettes, L-shaped rooms, the map panning, a second kind of token or a bigger pocket, and the Imprint upgrades beyond the numbers (a longer platform, more than one at a time, a longer life, bouncing). Width and duration are read when a platform is placed, but no room gives either upgrade now (the width pickup went with the old room 5), so Imprint is the only upgrade you can get today.
