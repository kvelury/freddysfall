# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Tried and working

Played in the browser and found good, so these are not listed line by line any more: Imprint in the browser (placing, the preview, the cross, the blink), saving and resuming, the solver and the "needs" lines, and movement and doors. A new problem in any of them goes back on this list.

## Tokens, locked doors and the 3TM (chunk 8)

Start with `?new-game=1` so an old save does not get in the way. A save from before chunk 8 is set aside as `save.json.bad` and the game starts new on its own.

The whole flow, in order:

- [ ] **Room 2 is shut.** You arrive from room 1 and the two doorways are shaded blocks with no glow. Walking into either stops you at the wall.
- [ ] **The blocks read as a barrier,** and not as wall or as a bug. Is the checker clear at 4× scale? Does it look like "not yet" and not "never"?
- [ ] **Taking the token opens the room.** The blocks shatter, the glow comes on, and the doors work. Does it feel instant and obvious?
- [ ] **The token shows on your body.** One diamond cut out of the top of the square. Does it read as a diamond at this size? Watch it while you jump and land (the body squashes).
- [ ] **Room 3 has two tokens,** one on the upper left platform and one on the lower right. Both are reachable by a normal player. The room can be left without them.
- [ ] **Three tokens look right on the body** (a triangle: top, left, right), and nothing overlaps.
- [ ] **A fourth token** stays where it is, with "You can carry 3 tokens" on screen once. Walk off and back onto it: it says it again. It is taken once you have spent one.
- [ ] **The 3TM in room 4** is bottom left. Does it read as a machine? A square with a bar on top, with three diamond openings.
- [ ] **Touching it with no tokens** says "3TM: 0 of 3 tokens", once, and nothing else happens.
- [ ] **Feeding it** is impossible to miss. Each token leaves your body, flies in an arc into an opening, and flashes. You cannot move meanwhile. Is the pace right (about half a second per token)? Is it too long with three in a row?
- [ ] **Bringing two tokens, leaving, and coming back with one** works: the two openings stay filled. Reload the page in between and check they are still filled.
- [ ] **The third token** makes the machine shake and flash three times, a spark flies to you, a line says what you got, and a line appears across the bottom of your body.
- Tokens and the Imprint line together cannot happen in the current rooms (the three tokens are spent to get Imprint), so only `token_test`'s pixel check covers that.
- [ ] **A spent 3TM** is drawn dotted, does nothing, and does not take a token from you.
- [ ] **Room 5 can be crossed** once you have Imprint, with a platform over the spikes, and the door in its right wall leads to room 6, which is empty. Is the pit crossable and fair, and can you come back across it?
- [ ] **Room 5 without Imprint** is a dead end on the left side. You can leave the way you came.
- [ ] **Dying while a 3TM is working** is not possible (you are frozen), but try dying right before touching one, and check the respawn.
- [ ] **Reloading in the middle of the flow.** After taking the room 2 token but before leaving it, reload: you are in room 2, with the token on your body and the doors open. Reload in room 3 with a token taken: it stays gone and still counts.
- [ ] **Imprint while the machine works.** Place a platform, touch the machine: the platform does not age while the machine is working.
- [ ] **An Imprint placed over a door block** is refused like any door.
- [ ] **A 3TM's size** against the player: walk behind it. It is not solid.
- [ ] **The validator** says what you expect: `tools/validate.sh` lists rooms 1 to 4 as needing nothing, and room 5's far ledge and room 6 as needing the three tokens and the 3TM. It takes about 9 seconds now.

## Respawn (chunks 5 and 7a)

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

## The solver (chunks 7b and 8)

- [ ] **A room that the validator calls shut but that a person can open.** The search leaves out placing a platform in mid-air and using two in a row. If you find a way across with either, we know which one to add.
- [ ] **A room that the validator opens but a person cannot.** The search ignores the limit of three tokens, and does not treat a blocked doorway as a wall for a body falling through a chain of doors.
- [ ] **A `~` cell in a real room.** None of the rooms use one. Try it on the pit in room 5 to see the solver shut the room again and the cross appear in the game.
- [ ] **Validator time.** `tools/validate.sh` takes about 9 seconds for 6 rooms. Check how it grows as you add rooms.

## Movement and doors (chunks 4 and 5)

- [ ] **The up-boost** of 180 px/s at ceiling doors: helps, or feels like a jump pad. The validator would still pass with a much weaker boost, because it only checks that some entry through the door lands.
- [ ] **Doors that are not level,** and a door with a wall right behind it.
- [ ] **Every way into a door,** not only the one the validator tried: slow, fast, from above, from the side.

## Things that were never built, so there is nothing to test yet

Gamepad and keyboard aiming, touch input, sound, the softer palettes, L-shaped rooms, the map panning, a second kind of token or a bigger pocket, and the Imprint upgrades beyond the numbers (a longer platform, more than one at a time, a longer life, bouncing). Width and duration are read when a platform is placed, but no room gives either upgrade now (the width pickup went with the old room 5), so Imprint is the only upgrade you can get today.
