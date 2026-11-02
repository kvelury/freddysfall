#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

python3 tools/test_runner.py version --templates
python3 tools/test_runner_test.py
python3 tools/test_runner.py import
python3 tools/test_runner.py tests
python3 tools/test_runner.py validate --no-cache

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

count=$(python3 -c 'import json; print(len(json.load(open("tests/test_manifest.json"))["tests"]))')
echo "CHECK pass: $count tests, uncached world validation, and web export"
