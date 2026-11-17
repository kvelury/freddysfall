#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# tools/render.sh [--preview] [ids]
#   --preview   geometry only, no solve: room_<id>_preview.png, world_preview.png
#   ids         draw only those rooms (and no world map)
# Without --preview the world is solved first, which can take long for a new room.
case "${1:-}" in -h|--help)
	sed -n '5,7p' "$0" | sed 's/^# \{0,1\}//'
	exit 0 ;;
esac
# A new class_name is not visible to a script run until the project is imported.
[ "${SKIP_IMPORT:-}" = 1 ] || godot --headless --path . --import >/dev/null 2>&1
exec godot --headless --path . --script tests/render.gd -- "$@"
