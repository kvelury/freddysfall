# Concept: aiming Imprint without a mouse

Kept for reference. Not part of the game, and not run by `tools/check.sh`. It
backs the plan in `docs/design/game-design.md`, "Aiming without a mouse
(planned, not built)". It was written against the code of 2026-10-26 and may
need changes to run after the code moves on.

- `imprint_aiming_concept.mp4`: the 52 s video the plan was agreed from. Dash-style (A) first, then build mode (C), each with keyboard and controller overlays.
- `imprint_slots.gd`: the slot table (`ConceptSlots`). Offsets are the numbers in the design doc.
- `imprint_demo.gd`: a scripted demo that builds four small rooms in memory, drives Freddy with the tests' scripted hooks and places platforms in the slots. Add `-- --debug` to run it headless and print where he lands, or `-- --shot=gap:dash` (`gap`, `catch` or `climb`; `dash` or `build`) to run one shot.
- `concept_overlay.gd`: draws the slot outlines and arrows in the world.
- `concept_hud.gd`: blacks out the view for title cards and logs captions and key state per frame to `build/concept/hud_log.json`.
- `compose.py`: draws the captions and the key or pad overlay at 1280x720 from that log, and encodes the MP4 and a GIF (needs `ffmpeg` and Pillow).

To record again, from the repo root. A game window opens for about a minute.

```sh
mkdir -p build/concept/frames
godot --path . --write-movie build/concept/frames/f.png --fixed-fps 60 --script tools/concept/imprint_demo.gd
python3 tools/concept/compose.py
```

Build mode's slow-motion in the demo is `Engine.time_scale`. That is fine for a
video but not for the game: see the design doc for why.
