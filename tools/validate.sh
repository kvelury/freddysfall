#!/bin/sh
# tools/validate.sh                         the world, using data/solver-cache (committed)
# tools/validate.sh --jobs N                N processes warm the pieces data/solver-cache lacks, then one solve reads it
# tools/validate.sh --no-cache              the same, worked out from scratch in one process
# tools/validate.sh --jobs N --fresh        the same into a fresh cache in build/
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

# Without --fresh the processes fill in the committed cache: a room whose file is
# still good is read, not solved again. --fresh works everything out in build/.
cache="data/solver-cache"
if [ "$fresh" -eq 1 ]; then
	cache="build/solver-cache-fresh"
	rm -rf "$cache"
fi
# The warm logs and the room times go in build/ whichever cache is used.
mkdir -p "$cache" build

# The cache is filled in pieces (see tests/validate.gd): each room's jumps without
# an air jump first, since its climbs read them, then the rest. Only the pieces
# the cache lacks are worked out, slowest room first (a new room counts as the
# slowest), N at a time, each in its own copy of the cache; then they are merged.
pieces="build/warm-pieces"
warm_phase() {
	rm -rf "$pieces" build/warm-*.log
	mkdir -p "$pieces"
	list=$(godot --headless --path . --script tests/validate.gd -- --plan --cache-dir="res://$cache" 2>/dev/null | sed -n 's/^piece //p' | grep -E "$1" || true)
	[ -n "$list" ] || return 0
	echo "warming $(echo "$list" | wc -l) pieces, $jobs at a time:" $list
	# shellcheck disable=SC2016
	if ! echo "$list" | xargs -P "$jobs" -I {} sh -c '
		name=$(echo "$1" | tr ":" "_")
		cp -r "$2" "$3/$name"
		godot --headless --path . --script tests/validate.gd -- --warm-piece="$1" --cache-dir="res://$3/$name" > "build/warm-$name.log" 2>&1 || { echo "warm $1 failed"; exit 1; }
		grep "^warm " "build/warm-$name.log"
	' _ {} "$cache" "$pieces"; then
		echo "a warm piece failed; see build/warm-*.log" >&2
		exit 1
	fi
	merged=$(godot --headless --path . --script tests/validate.gd -- --merge="res://$pieces" --cache-dir="res://$cache" 2>/dev/null | grep -E "^(merge|warn|FAIL)" || true)
	echo "$merged"
	case "$merged" in
		*FAIL*|"") echo "merging the warm pieces failed" >&2; exit 1 ;;
	esac
	rm -rf "$pieces"
}
warm_phase ':jumps0$'
warm_phase ':(jumps1|climb[01])$'
# shellcheck disable=SC2086
exec godot --headless --path . --script tests/validate.gd -- $rest --cache-dir="res://$cache"
