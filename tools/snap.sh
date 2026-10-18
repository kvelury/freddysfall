#!/bin/sh
# A real in-game frame of one room, written to build/snaps/room_<id>.png.
# Opens a window for about a second, so run it on your own machine.
set -eu
if [ $# -ne 1 ]; then
    echo "usage: tools/snap.sh <room id>" >&2
    exit 2
fi
cd "$(dirname "$0")/.."
room=$1
tmp="build/snaps/.tmp_$room"
rm -rf "$tmp"
mkdir -p "$tmp"
godot --path . --write-movie "$tmp/frame.png" --fixed-fps 60 --quit-after 30 -- --room="$room" >/dev/null 2>&1
last=$(ls "$tmp"/*.png | tail -1)
mv "$last" "build/snaps/room_$room.png"
rm -rf "$tmp"
echo "build/snaps/room_$room.png"
