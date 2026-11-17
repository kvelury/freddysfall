#!/bin/sh
# Solves the world at <ref> and in the working tree, without the cache, and
# diffs everything the solver worked out (tests/lib/solver_dump.gd). Prints
# nothing and exits 0 when the two agree and both solves finished. A solver
# change that is meant to be exact must leave this empty.
#
#   tools/solver_diff.sh origin/main
#
# Exit 0 both dumps complete and equal; 1 they differ; 2 a solve failed (a
# crash, a world that did not load, a missing or partial dump): no comparison.
# Each side runs tests/lib/solver_dump_main.gd, copied into the base with
# solver_dump.gd, so an old ref needs nothing newer than the solver itself.
# SOLVER_DIFF_WORLD=res://tests/fixtures/worlds/climb tools/solver_diff.sh <ref>
# compares a small fixture world in seconds instead of the whole world.
# Dumps are deleted before each run, so a failed run can never leave
# yesterday's dump to be compared.
set -eu
cd "$(dirname "$0")/.."
if [ $# -lt 1 ]; then
	echo "usage: tools/solver_diff.sh <ref>" >&2
	exit 2
fi
ref="$1"
out="build/solver-diff"
base="$out/base"
mkdir -p "$out"
rm -f "$out"/base.json "$out"/head.json "$out"/*.partial
if [ -d "$base" ]; then
	git -C "$base" checkout --quiet --detach "$ref"
else
	git worktree add --quiet --detach "$base" "$ref"
fi
mkdir -p "$base/tests/lib"
world=""
[ -z "${SOLVER_DIFF_WORLD:-}" ] || world="--world=$SOLVER_DIFF_WORLD"
cp tests/lib/solver_dump_main.gd tests/lib/solver_dump.gd "$base/tests/lib/"

godot --headless --path "$base" --import > "$out/base-import.log" 2>&1
godot --headless --path . --import > "$out/head-import.log" 2>&1
# Both solves run at once; each is one process on one core.
godot --headless --path "$base" --script tests/lib/solver_dump_main.gd -- "--dump=$PWD/$out/base.json" $world > "$out/base.log" 2>&1 &
base_pid=$!
godot --headless --path . --script tests/lib/solver_dump_main.gd -- "--dump=$PWD/$out/head.json" $world > "$out/head.log" 2>&1 &
head_pid=$!
failed=0
for side in base head; do
	pid=$base_pid
	[ "$side" = head ] && pid=$head_pid
	code=0
	wait "$pid" || code=$?
	if [ "$code" -ne 0 ] || [ ! -s "$out/$side.json" ] || ! grep -q '"complete": true' "$out/$side.json"; then
		echo "solver_diff: the $side solve did not finish (exit $code); see $out/$side.log" >&2
		failed=1
	fi
done
[ "$failed" -eq 0 ] || exit 2
diff -u "$out/base.json" "$out/head.json"
