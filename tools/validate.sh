#!/bin/sh
# tools/validate.sh                         the world, using build/solver-cache
# tools/validate.sh --no-cache              the same, worked out from scratch
# tools/validate.sh --jobs N --fresh        N processes warm a fresh cache, then one solve reads it
# --strict-ledges and --dump=<path> are passed through to the solve.
set -eu
cd "$(dirname "$0")/.."
# A new class_name is not visible to a script run until the project is imported.
# check.sh imports once and sets SKIP_IMPORT=1.
[ "${SKIP_IMPORT:-}" = 1 ] || godot --headless --path . --import >/dev/null 2>&1

jobs=1
fresh=0
rest=""
while [ $# -gt 0 ]; do
	case "$1" in
		--jobs)
			jobs="$2"
			shift 2
			;;
		--jobs=*)
			jobs="${1#--jobs=}"
			shift
			;;
		--fresh)
			fresh=1
			shift
			;;
		*)
			rest="$rest $1"
			shift
			;;
	esac
done

# --no-cache is one process and ignores the cache: there is nothing to share.
case " $rest " in
	*" --no-cache "*) jobs=1; fresh=0 ;;
esac

if [ "$jobs" -le 1 ] && [ "$fresh" -eq 0 ]; then
	# shellcheck disable=SC2086
	exec godot --headless --path . --script tests/validate.gd -- $rest
fi

cache="build/solver-cache-fresh"
rm -rf "$cache"
mkdir -p "$cache"
groups=$(python3 - "$jobs" << 'PY'
import json
import sys

jobs = max(1, int(sys.argv[1]))
rooms = json.load(open("data/world.json"))["rooms"]
ids = [str(room["id"]) for room in rooms]
times = {}
try:
    times = json.load(open("build/room-times.json"))
except OSError:
    pass
ids.sort(key=lambda room_id: (-float(times.get(room_id, 0)), room_id))
groups = [[] for _ in range(jobs)]
for index, room_id in enumerate(ids):
    groups[index % jobs].append(room_id)
for group in groups:
    if group:
        print(",".join(group))
PY
)

n=0
pids=""
for group in $groups; do
	godot --headless --path . --script tests/validate.gd -- --warm="$group" --cache-dir="res://$cache" > "build/warm-$n.log" 2>&1 &
	pids="$pids $!"
	n=$((n + 1))
done
failed=0
for pid in $pids; do
	wait "$pid" || failed=1
done
if [ "$failed" != 0 ]; then
	echo "a warm process failed; see build/warm-*.log" >&2
	cat build/warm-*.log >&2 || true
	exit 1
fi
# shellcheck disable=SC2086
exec godot --headless --path . --script tests/validate.gd -- $rest --cache-dir="res://$cache"
