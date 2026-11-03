#!/bin/sh
# Solves the world at <ref> and in the working tree, without the cache, and
# diffs everything the solver worked out (tests/lib/solver_dump.gd). Prints
# nothing and exits 0 when the two agree. A solver change that is meant to be
# exact must leave this empty.
#
#   tools/solver_diff.sh origin/main
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
if [ -d "$base" ]; then
	git -C "$base" checkout --quiet --detach "$ref"
else
	git worktree add --quiet --detach "$base" "$ref"
fi
# The base may be older than the dump, so it gets the working tree's copy of
# the script that writes it.
mkdir -p "$base/tests/lib"
cp tests/validate.gd "$base/tests/validate.gd"
cp tests/lib/solver_dump.gd "$base/tests/lib/solver_dump.gd"

godot --headless --path "$base" --import > "$out/base-import.log" 2>&1
godot --headless --path . --import > "$out/head-import.log" 2>&1
# Both solves run at once; each is one process on one core.
godot --headless --path "$base" --script tests/validate.gd -- --no-cache "--dump=$PWD/$out/base.json" > "$out/base.log" 2>&1 &
base_pid=$!
godot --headless --path . --script tests/validate.gd -- --no-cache "--dump=$PWD/$out/head.json" > "$out/head.log" 2>&1 &
head_pid=$!
wait "$base_pid" || true
wait "$head_pid" || true
for side in base head; do
	if [ ! -s "$out/$side.json" ]; then
		echo "solver_diff: the $side solve wrote no dump; see $out/$side.log" >&2
		exit 2
	fi
done
diff -u "$out/base.json" "$out/head.json"
