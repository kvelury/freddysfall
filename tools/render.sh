#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# tools/render.sh [--solve] [ids]
#   (default)   geometry only, no solve, no cache: room_<id>_preview.png, world_preview.png
#   --solve     solve the world first and mark what it reaches: room_<id>.png, world.png
#               (optional; reads the committed solver cache, and can take very long for a new large room)
#   ids         draw only those rooms (and no world map)
# A preview proves nothing about reachability.
case "${1:-}" in -h|--help)
	sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//'
	exit 0 ;;
esac
# A new class_name is not visible to a script run until the project is imported.
[ "${SKIP_IMPORT:-}" = 1 ] || godot --headless --path . --import >/dev/null 2>&1
exec godot --headless --path . --script tests/render.gd -- "$@"
