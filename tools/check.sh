#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# tools/check.sh               the whole gate: tests, strict validation, web export
# tools/check.sh --tests-only  just the tests

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
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
LOGS=build/test-logs
rm -rf "$LOGS"
mkdir -p "$LOGS"
SLOW="shaft_test emitter_test imprint_solver_test cache_test game_over_test hazard_test save_room_test platform_test title_card_test"
for name in $SLOW; do
	if [ -f "tests/$name.gd" ]; then
		echo "$name"
	fi
done > "$LOGS/order.txt"
for path in tests/*_test.gd; do
	name=$(basename "$path" .gd)
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
if [ "${1:-}" = "--tests-only" ]; then
	echo "TESTS pass: $COUNT tests"
	exit 0
fi

echo "==> validate (no cache, every ledge reachable)"
./tools/validate.sh --no-cache --strict-ledges

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

echo "CHECK pass: $COUNT tests, uncached world validation, and web export"
