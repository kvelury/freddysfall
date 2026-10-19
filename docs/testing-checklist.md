# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Imprint in the browser (7a)

- [ ] **The click lands where the cursor is.** Place a platform at the corners of the screen and at the middle. The platform's left end should be the cell under the cursor.
- [ ] **Different window sizes.** Resize the browser, go fullscreen, try a size that adds black bars. The cursor cell must still match what you point at. Headless tests never scale the window.
- [ ] **Cursor hiding.** The system cursor hides while Imprint is active and comes back when it is not. Check what happens when the mouse leaves the page and returns, and when you open the map (Tab or M), where the game is paused.
- [ ] **First click on the page.** Does clicking the page to focus it place an Imprint by accident?
- [ ] **The preview before the mouse has moved.** Nothing should be drawn at the top-left corner on load.
- [ ] **Preview speed.** Sweep the mouse quickly across the room. Each cell change can run up to about 25 jump simulations. Watch F3 for a drop in FPS or a rise in frame time, in the browser and not only on desktop.
- [ ] **The preview is honest.** A filled platform should always be landable with the jump you would make. Try twenty. Also note any dotted platform that you can in fact land on (a miss that is allowed, but worth knowing about).
- [ ] **The cross.** On solid floor, over spikes, on a door, in a wall, on the player. It should read clearly each time and a click should do nothing.
- [ ] **Blink and shatter.** The last second blinks, then it shatters. Does 4 seconds feel right? Does the blink read?
- [ ] **Standing on it when it breaks.** You fall, and nothing odd happens (stuck, bounce, teleport).
- [ ] **Edges of the platform.** Jumping into one from below, from the side, and from a running start. Walking off its end. Placing one that touches the ceiling or a wall.
- [ ] **Placed on top of a pickup,** and next to a door. The door margin should keep the doorway open.
- [ ] **Placing while moving.** In the air, while running, right as you land.
- [ ] **Imprint across a door.** Place one, then walk through a door. It should be gone in the new room and not drawn mid-slide.
- [ ] **Imprint and death.** Place one and die. It should shatter with you.

## Respawn (chunks 5 and 7a)

- [ ] **Dying right after a door.** The respawn spot may be in the previous room. Check that it feels right, and that you do not die twice.
- [ ] **A respawn that is not safe.** Make one by standing on an Imprint over spikes and then dying; you were shown this fixed. Also try standing half on a ledge and half on an Imprint.
- [ ] **Falling out of a room** through a hole in the floor that leads nowhere, in a room with a door below.
- [ ] **The step-back.** If you can make two deaths in a row, check that you end up on real floor and not in a loop.

## Saving and starting (chunk 6)

- [ ] **Reload resumes.** Take the pickup in room 2, reload: you are in room 2, with Imprint, and the pickup is gone. Tested headless only.
- [ ] **Save on room entry.** Walk to room 4, reload: you should be in room 4 where you came in.
- [ ] **`?new-game=1`.** It should start in room 1, with no Imprint, and the next room entry should replace the old save.
- [ ] **`?room=5`.** A test start: it must not read the save or change it. Reload without the parameter afterwards and check your save is untouched.
- [ ] **Clearing the browser's site data** and starting again.
- [ ] **A damaged save.** In the browser's storage tools, edit or break the save file and reload. It should start a new game and keep `save.json.bad`.
- [ ] **A save from before Imprint existed.** Yours has the room 5 pickup taken, which no longer exists. It should load without trouble.
- [ ] **The pickup message** in the real window: where it sits, how long it stays, whether it overlaps anything.
- [ ] **F3** shows the Imprint line, and it changes when you take the pickup.

## Debug tools

- [ ] **F4, a room number, Enter** in a debug build, in a real window. Digits, Escape, a room that does not exist.
- [ ] **A load-error overlay.** In a debug build, break a room file on purpose and see the errors appear on screen. Never seen outside of tests.
- [ ] **`godot --path . -- --room=3`** on the desktop build.

## Rooms from drawings

- [ ] **The whole drawing-to-room routine on a real drawing.** Nobody has run the protocol in `AGENTS.md` on a real photo. Expect to change the instructions after the first try: how a drawing is read, how rounding is reported, what the key should look like.
- [ ] **A drawing with a pickup and a hazard in it,** to try the legend lines and the cheat-sheet.
- [ ] **A room of two or more screens** and a room with a door that spans a screen boundary, drawn by hand.

## The solver and validator (chunk 7b)

- [ ] **Room 6 can be crossed by a person.** The validator says Imprint opens it. Nobody has done it. Take the pickup in room 2, go through room 5's new right door, and cross the pit with a platform over the spikes. Then come back across it.
- [ ] **Room 6's pickup,** the width 3 upgrade on the far side, and what a wider platform feels like.
- [ ] **A room that the validator calls shut but that a person can open.** The search leaves out placing a platform in mid-air and using two in a row. If you find a way across with either, we know which one to add.
- [ ] **A `~` cell in a real room.** None of the rooms use one. Try it on the pit in room 6 to see the solver shut the room again and the cross appear in the game.
- [ ] **Validator time.** `tools/validate.sh` takes about 5 seconds for 6 rooms. Check how it grows as you add rooms.
- [ ] **The "needs" lines** make sense to you when you read them.

## Movement and doors (chunks 4 and 5)

- [ ] **The up-boost** of 180 px/s at ceiling doors: helps, or feels like a jump pad. The validator would still pass with a much weaker boost, because it only checks that some entry through the door lands.
- [ ] **Doors that are not level,** and a door with a wall right behind it.
- [ ] **Every way into a door,** not only the one the validator tried: slow, fast, from above, from the side.
- [ ] **Corner correction** (stepping onto ledges by a few pixels) after the one-resolver change, on all rooms.

## Things that were never built, so there is nothing to test yet

Gamepad and keyboard aiming, touch input, sound, the softer palettes, L-shaped rooms, the map panning, the tokens and the 3TM, and the Imprint upgrades beyond the numbers (a longer platform, more than one at a time, a longer life, bouncing). Width and duration are read when a platform is placed, so the width 3 pickup in room 6 is the one upgrade you can feel today.
