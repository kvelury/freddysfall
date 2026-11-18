#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# tools/check.sh               the gate: tests, the world loads, web export. No solver.
# tools/check.sh --tests-only  just the tests
# tools/check.sh --quick       the same as no flag (kept so old habits still work)
# tools/check.sh --solver      also the solver tests and the whole-world solve
#                              (reachability). OPTIONAL: run it at milestones, not
#                              while iterating on a room or power. Reads the
#                              committed data/solver-cache; a stale cache only warns.
# tools/check.sh --fresh       --solver with the solve worked out from scratch
#                              (ignores the committed cache; slow, hours with rooms 18 and 19)
# The solver is advisory: the author playtests rooms. CI runs this without a
# flag; the solver runs in the manual "Solver" workflow (.github/workflows/solver.yml).
SOLVER=0
FRESH=0
TESTS_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--solver) SOLVER=1 ;;
		--fresh) SOLVER=1; FRESH=1 ;;
		--tests-only) TESTS_ONLY=1 ;;
		--quick) ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

echo "==> import"
godot --headless --path . --import

# Imported once: the tests, validate.sh and build_web.sh reuse it.
export SKIP_IMPORT=1

# Every tests/*_test.gd runs, each in its own Godot process, JOBS at a time
# (the machine's cores unless set), with --fixed-fps 60: each frame is exactly
# 1/60 s of game time, so timers, tweens and waits do not depend on the machine
# and cost no real time. The slowest start first so none is left
# running alone at the end. Each writes build/test-logs/<name>.log, and the
# log of every test that failed is printed at the end.
# nproc is Linux; macOS has sysctl.
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
JOBS="${JOBS:-$CORES}"
LOGS=build/test-logs
rm -rf "$LOGS"
mkdir -p "$LOGS"
# A test that builds a ReachGraph or reads the solver cache is a tests/solver_*_test.gd
# file and runs only with --solver, so editing a room or a power never breaks the
# default gate through the solver.
leaks=$(grep -l -E 'ReachGraph|SolverCache|StrictLedges|CacheWarm' tests/*_test.gd | grep -v '^tests/solver_' || true)
if [ -n "$leaks" ]; then
	echo "these tests use the solver but are not named tests/solver_*_test.gd: $leaks"
	exit 1
fi
SLOW="shaft_test emitter_test solver_test solver_cache_test solver_emitter_test game_over_test hazard_test save_room_test platform_test title_card_test"
for name in $SLOW; do
	case "$name" in solver_*) [ "$SOLVER" = 1 ] || continue ;; esac
	if [ -f "tests/$name.gd" ]; then
		echo "$name"
	fi
done > "$LOGS/order.txt"
for path in tests/*_test.gd; do
	name=$(basename "$path" .gd)
	case "$name" in solver_*) [ "$SOLVER" = 1 ] || continue ;; esac
	grep -qx "$name" "$LOGS/order.txt" || echo "$name"
done >> "$LOGS/order.txt"
COUNT=$(wc -l < "$LOGS/order.txt" | tr -d ' ')
touch "$LOGS/.started"

echo "==> $COUNT tests, $JOBS at a time"
xargs -P "$JOBS" -n 1 sh -c '
	name="$1"
	begun=$(date +%s)
	if godot --headless --path . --fixed-fps 60 --script "tests/$name.gd" > "build/test-logs/$name.log" 2>&1; then
		result=pass
	else
		result=FAIL
	fi
	echo "$result $name $(( $(date +%s) - begun )) s" | tee "build/test-logs/$name.status"
' _ < "$LOGS/order.txt"

failed=0
for status in "$LOGS"/*.status; do
	if grep -q "^FAIL" "$status"; then
		name=$(basename "$status" .status)
		echo "==> tests/$name.gd failed:"
		cat "$LOGS/$name.log"
		failed=1
	fi
done
ran=$(ls "$LOGS"/*.status 2>/dev/null | wc -l | tr -d ' ')
if [ "$ran" != "$COUNT" ]; then
	echo "only $ran of $COUNT tests reported a result"
	failed=1
fi
# A test that imports would race the others on .godot/; none may.
if [ -n "$(find .godot -newer "$LOGS/.started" -print -quit)" ]; then
	echo "a test changed .godot/ (it imported something); tests must run on the import done above"
	failed=1
fi
# Each user:// file belongs to one test, so they can run at once.
shared=$(grep -o 'user://[A-Za-z0-9_./-]*' tests/*.gd | sort -u | cut -d: -f2- | sort | uniq -d)
if [ -n "$shared" ]; then
	echo "more than one test uses: $shared"
	failed=1
fi
if [ "$failed" != 0 ]; then
	exit 1
fi
if [ "$TESTS_ONLY" = 1 ]; then
	echo "TESTS pass: $COUNT tests"
	exit 0
fi

echo "==> world loads (no solver)"
./tools/validate.sh --load-only

if [ "$SOLVER" = 1 ]; then
	if [ "$FRESH" = 1 ]; then
		echo "==> solver (no cache, every ledge reachable)"
		./tools/validate.sh --jobs "$CORES" --fresh --strict-ledges
	else
		echo "==> solver (committed solver cache, every ledge reachable)"
		./tools/validate.sh --jobs "$CORES" --strict-ledges
		# The cache is committed so a later solve only redoes what changed. If this
		# run had to write any of it, commit it to save the next run the work. It is
		# never an error: the solver is optional.
		stale=$(git status --porcelain -- data/solver-cache)
		if [ -n "$stale" ]; then
			echo "$stale"
			echo "note: data/solver-cache was refreshed by this solve; commit it (git add data/solver-cache) if you want to keep it."
		fi
	fi
fi

echo "==> web export"
./tools/build_web.sh

echo "==> web export integrity"
python3 - << 'PY'
import hashlib
import os
import re
import sys
from pathlib import Path

root = Path(".")
preset = (root / "export_presets.cfg").read_text()
if 'include_filter="*.txt"' not in preset:
    sys.exit('export_presets.cfg is missing include_filter="*.txt"')

web = root / "build/web"
for name in ("index.html", "index.js", "index.pck", "index.wasm"):
    path = web / name
    if not path.is_file() or path.stat().st_size == 0:
        sys.exit(f"missing or empty web export: {path}")

html = (web / "index.html").read_text()
if "e.key==='Tab'" not in html:
    sys.exit("index.html is missing the Tab key patch")

js_match = re.search(r'src="index\.js\?v=([0-9a-f]{12})"', html)
executable_match = re.search(r'"executable":"(g[0-9a-f]{12})"', html)
if js_match is None or executable_match is None:
    sys.exit("index.html is missing its cache-tagged JavaScript or executable")
digest = js_match.group(1)
tag = executable_match.group(1)
if tag != f"g{digest}":
    sys.exit(f"web cache tags disagree: index.js uses {digest}, executable uses {tag}")

pck = web / "index.pck"
wasm = web / "index.wasm"
pck_bytes = pck.read_bytes()
if b"data/rooms/s1.txt" not in pck_bytes:
    sys.exit("index.pck does not contain data/rooms/s1.txt")
for folder in (b"res://tests/", b"res://tools/", b"res://docs/"):
    if folder in pck_bytes:
        sys.exit(f"index.pck contains {folder.decode()}; the Web preset's exclude_filter should keep it out")
if hashlib.sha256(pck_bytes).hexdigest()[:12] != digest:
    sys.exit("index.html cache tag does not match index.pck")

sizes_match = re.search(
    r'"fileSizes":\{"([^"]+\.pck)":(\d+),"([^"]+\.wasm)":(\d+)\}',
    html,
)
if sizes_match is None:
    sys.exit("index.html is missing tagged PCK and WASM sizes")
if sizes_match.group(1) != f"{tag}.pck" or int(sizes_match.group(2)) != pck.stat().st_size:
    sys.exit("index.html has the wrong tagged PCK size")
if sizes_match.group(3) != f"{tag}.wasm" or int(sizes_match.group(4)) != wasm.stat().st_size:
    sys.exit("index.html has the wrong tagged WASM size")

for suffix in (".pck", ".wasm", ".audio.worklet.js", ".audio.position.worklet.js"):
    base = web / f"index{suffix}"
    tagged = web / f"{tag}{suffix}"
    if not base.is_file() or base.stat().st_size == 0:
        sys.exit(f"missing or empty web export: {base}")
    if not tagged.exists() or tagged.stat().st_size == 0:
        sys.exit(f"missing or empty tagged web export: {tagged}")
    if tagged.is_symlink() and os.path.realpath(tagged) != os.path.realpath(base):
        sys.exit(f"{tagged.name} does not point to {base.name}")
    if suffix in (".pck", ".wasm") and tagged.stat().st_size != base.stat().st_size:
        sys.exit(f"{tagged.name} and {base.name} have different sizes")

print(f"web export ok ({tag})")
PY

if [ "$SOLVER" = 1 ]; then
	echo "CHECK pass: $COUNT tests, world loaded and solved, and web export"
else
	echo "CHECK pass: $COUNT tests, world loads, and web export. Solver not run (optional: tools/check.sh --solver)."
fi
