# Freddy's Fall

A sidescrolling metroidvania adventure. You move through a network of single-screen rooms, and new abilities open paths that were out of reach. The look is black and white pixel art: solid blocks, a square for the player, and small effects where they help you see what matters.

This repository is the Godot 4 game. It runs in a desktop window or in any modern browser.

## Play

You need [Godot 4.7](https://godotengine.org/) with the web export templates installed.

```sh
./tools/build_web.sh
./tools/serve.sh
```

That exports a threads-off web build and opens it at http://localhost:8060. The same project also runs from the Godot editor with Play.

## Controls

| Action | Keys |
| --- | --- |
| Move | A / D, or Left / Right |
| Jump | Space, W, or Up |
| Map | Hold Tab or M |
| Frame rate | F3 |

Down is reserved. Letting go of jump early makes a short hop. Holding it makes the full leap, and a running jump carries farther than a standing one.

## This version

Version 0.1 is the first playable slice: two rooms, a halo marking the exit, and a camera that slides from one screen to the next. Holding the map pauses the game and shows the rooms you have visited.

Rooms are ASCII files in `data/rooms/`, listed with their map position in `data/world.json`. The playfield is 320×180, scaled up with nearest-neighbor filtering. Physics runs at a fixed 60 ticks per second, so the movement stays the same when the display is 60, 120, or 144 Hz.

Still ahead: placing a temporary platform to reach new ground, and a softer two-color palette for playing in the dark (see `docs/plans/soft-duotone-palettes.md`).
