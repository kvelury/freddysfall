#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# A new class_name is not visible to a script run until the project is imported.
godot --headless --path . --import >/dev/null 2>&1
# Room ids after the script name draw only those rooms: tools/render.sh 3 4
exec godot --headless --path . --script tests/render.gd -- "$@"
