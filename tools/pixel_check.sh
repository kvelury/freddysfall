#!/bin/sh
# The pixel check: draws scripted scenarios with a renderer and checks every
# world pixel is drawn as one block (the world-pixel grid) and that the frames
# equal the baseline: frames recorded earlier, kept as world pixels (320x180).
#
#   tools/pixel_check.sh --baseline   capture the baseline on a commit you trust (one pixel per world pixel)
#   tools/pixel_check.sh --shapes     print the one-bit pictures of the polygon shapes
#   tools/pixel_check.sh              compare against the baseline, and save UI frames
#
# Frames are written to build/pixel-baseline/ and build/pixel-check/. It needs a
# display: with none it runs under xvfb-run.
set -eu
cd "$(dirname "$0")/.."
mode=compare
case "${1:-}" in
    --baseline) mode=baseline ;;
    --shapes) mode=shapes ;;
    "") ;;
    *) echo "usage: tools/pixel_check.sh [--baseline|--shapes]" >&2; exit 2 ;;
esac
python3 tools/test_runner.py import
exec python3 tools/test_runner.py pixel "$mode"
