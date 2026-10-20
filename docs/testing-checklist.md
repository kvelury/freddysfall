# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Tried and working

Played in the browser and found good, so these are not listed line by line any more: Imprint in the browser (placing, the preview, the cross, the blink), saving and resuming, the solver and the "needs" lines, movement and doors, the whole world map of PR #17 (rooms 1 to 7, the exit rules, the tokens on the body, the 3TM and its feeding, and the spent machine), and the Imprint look of PR #18 (the dotted cursor, placed platforms drawn over it, the countdown lines, and the blink). A new problem in any of them goes back on this list.

## Map zoom and new game (PR #20)

Hold Tab (or M) for the map. Up or W zooms in, Down or S zooms out.

- [ ] **Three levels.** Out shows the whole map, including all of room 7, with nothing cut off. Middle is the view you know. In is twice that. Is twice the right amount, or is it too much?
- [ ] **Out and Middle look the same at the start,** when you have only visited one or two rooms. Is that confusing, or fine?
- [ ] **It is sharp at every level.** The outlines are one pixel, the door gaps are clear, and rooms that were apart still have a gap between them. Check Out especially: it is not a whole number scale.
- [ ] **The marker stays in its room at every level.** Go to the bottom of room 7, then hold the map and step through Out, Middle and In. The marker should be on room 7's drawn rectangle each time, and Out should show every room. (The first version drew the map one zoom step behind the marker.)
- [ ] **In follows you.** In room 7 (the tall one), zoomed in, the view is on your marker. Does the marker read at 2x, where it is still one pixel?
- [ ] **The legend** in the bottom-right corner reads at 4x: an up arrow and a magnifying glass with a plus over a down arrow and one with a minus. Is it clear which key does what? The row that can do nothing more goes grey. Is that clear, or noise?
- [ ] **The level is remembered.** Set Out, let go of Tab, and hold it again: still Out. Reload the page (no `?new-game=1`): still Out.
- [ ] **A new game wipes it.** Load with `?new-game=1`: back in room 1 with nothing, and the map at Middle. Then reload with the plain address: it is still the fresh game (the old save is gone).
- [ ] **A plain reload keeps the game,** the map's level included.
- [ ] **Up, Down, W and S do not move you** while the map is open, and Up or W does not jump you when you let go of Tab.

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
- [ ] **Validator time.** `tools/validate.sh` takes about 16 seconds for 7 rooms. Check how it grows as you add rooms.

## Movement and doors

- [ ] **The up-boost** of 180 px/s at ceiling doors: helps, or feels like a jump pad. The validator would still pass with a much weaker boost, because it only checks that some entry through the door lands.
- [ ] **Doors that are not level,** and a door with a wall right behind it.
- [ ] **Every way into a door,** not only the one the validator tried: slow, fast, from above, from the side.

## Things that were never built, so there is nothing to test yet

Room 7's title card and its 3TM, gamepad and keyboard aiming, touch input, sound, the softer palettes, L-shaped rooms, the map panning, a second kind of token or a bigger pocket, and the Imprint upgrades beyond the numbers (a longer platform, more than one at a time, a longer life, bouncing). Width and duration are read when a platform is placed, but no room gives either upgrade now (the width pickup went with the old room 5), so Imprint is the only upgrade you can get today.
