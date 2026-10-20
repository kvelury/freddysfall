# Testing checklist: things nobody has tried yet

Everything here passed its headless tests or was reported as unverified in a pull request. None of it has been confirmed by playing the real build, unless a line says who did. Do a round with `tools/build_web.sh` and `tools/serve.sh`, then http://localhost:8060. Tick a line when you have seen it work, or write down what broke.

"Headless" means a script drove the game with no window and no mouse. It proves the logic, not what a person sees or feels.

## Tried and working

Played in the browser and found good, so these are not listed line by line any more: Imprint in the browser (placing, the preview, the cross, the blink), saving and resuming, the solver and the "needs" lines, and movement and doors. A new problem in any of them goes back on this list.

## The new world map (PR #17)

Start with `?new-game=1`. A save from before this PR can be inside a wall of the new rooms.

- [ ] **Room 2's new floor door.** It sits beside the right door, with three cells of floor between them. Before the token it is a block like the other two. After it, a hole: jump it going right, and check you do not fall in by accident when you come back from room 3.
- [ ] **Dropping from 2 into 5** lands you on the upper platform, even at the edge of the hole. You can climb back up through room 5's three platforms to room 2, and you can leave through 5's right door to room 4.
- [ ] **Room 3's moved hole** (cols 6 to 12, by its left door). Walking in from room 2 you meet it after about five cells. Is a running jump over it fair? Dropping in leads to room 4, and room 4's zigzag climbs back to it.
- [ ] **Room 3's lone token** is on the lower right platform, all the way across. Is the way across the hole and along the room clear enough?
- [ ] **Room 5's token** is on the middle platform. Is it easy to get to without Imprint?
- [ ] **The 3TM beside room 4's new left door.** You arrive from room 5 and the machine is three cells away. Does running through it by accident (with no tokens) feel annoying? It shows "0 of 3 tokens" each time.
- [ ] **Crossing room 5's spikes with Imprint,** from the middle platform to the left floor. One Imprint platform in the gap should be enough. Without Imprint it must not be possible.
- [ ] **Crossing back** from the left floor to the middle platform. This works in the solver and needs a short run-up on a four-cell floor.
- [ ] **Room 6's wall.** Without Imprint you cannot get onto the roof. With it, a platform by the wall gets you up, then walk off the end and fall into the hole. Does it read that the hole is the way on?
- [ ] **The fall into room 7.** About 2.5 seconds in the air. The camera follows, the landing is on a floor, and nothing is wrong at the top or bottom of the fall. Room 7 is a dead end: you cannot get back up yet. (Dying there, if you can, puts you back on room 7's floor or in room 6.)
- [ ] **Imprint over room 5's spikes** and dying on one: respawn on the right-hand floor, not in the air.
- [ ] **Room 5's left floor** has no safe respawn spot (it is next to spikes and a door). If you die after crossing, you come back on the right side of the pit. Is that acceptable?
- [ ] **The world map overlay** (Tab or M) shows the seven rooms as drawn, with room 7 four screens tall.

The whole token flow, in order:

- [ ] **Room 2 is shut.** You arrive from room 1 and the three doorways are shaded blocks with no glow. Walking into any stops you at the wall.
- [ ] **The blocks read as a barrier,** and not as wall or as a bug. Is the checker clear at 4x scale?
- [ ] **Taking the token opens the room.** The blocks shatter, the glow comes on, and the doors work.
- [ ] **The token shows on your body.** One diamond cut out of the top of the square. Does it read as a diamond at this size?
- [ ] **Three tokens look right on the body** (a triangle: top, left, right), and nothing overlaps.
- [ ] **A fourth token** stays where it is, with "You can carry 3 tokens" on screen once. You can only test it by taking a token and then going back for another before using the 3TM (you only need three, so the tokens are all you have).
- [ ] **The 3TM in room 4** reads as a machine: a square with a bar on top, with three diamond openings.
- [ ] **Touching it with no tokens** says "0 of 3 tokens", once, and nothing else happens.
- [ ] **Feeding it** is impossible to miss. Each token leaves your body, flies in an arc into an opening, and flashes. You cannot move meanwhile. Is the pace right (about half a second per token)?
- [ ] **Bringing two tokens, leaving, and coming back with one** works: the two openings stay filled. Reload the page in between and check they are still filled.
- [ ] **The third token** makes the machine shake and flash three times, a spark flies to you, a line says what you got, and a line appears across the bottom of your body.
- [ ] **A spent 3TM** is drawn dotted, does nothing, and does not take a token from you.
- [ ] **Reloading in the middle of the flow.** After taking the room 2 token but before leaving it, reload: you are in room 2, with the token on your body and the doors open.
- [ ] **Imprint while the machine works.** Place a platform, touch the machine: the platform does not age while the machine is working.
- Tokens and the Imprint line together cannot happen in the current rooms (the three tokens are spent to get Imprint), so only `token_test`'s pixel check covers that.
- [ ] **The validator** says what you expect: `tools/validate.sh` lists rooms 1 to 5 as needing nothing, and room 5's left floor, room 6 and room 7 as needing the three tokens and the 3TM. It takes about 16 seconds now.

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
