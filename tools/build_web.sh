#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
godot --headless --path . --import
mkdir -p build/web
godot --headless --path . --export-release "Web" "build/web/index.html"
python3 - << 'PY'
import hashlib
import os
import re
from pathlib import Path

web = Path("build/web")
html_path = web / "index.html"
text = html_path.read_text()
snippet = "<script>window.addEventListener('keydown',function(e){if(e.key==='Tab')e.preventDefault();},true);</script>"
if "e.key==='Tab'" not in text:
    text = text.replace("</head>", snippet + "\n</head>", 1)

# The engine fetches index.pck and index.wasm by name, and browsers keep the
# previous response. A new pack with the same name is played as the old game.
pck = (web / "index.pck").read_bytes()
wasm_size = (web / "index.wasm").stat().st_size
digest = hashlib.sha256(pck).hexdigest()[:12]
tag = f"g{digest}"
for suffix in (".pck", ".wasm", ".audio.worklet.js", ".audio.position.worklet.js"):
    src = web / f"index{suffix}"
    dst = web / f"{tag}{suffix}"
    if dst.is_symlink() or dst.exists():
        dst.unlink()
    os.symlink(src.name, dst)
for stale in web.glob("g*"):
    if stale.name.startswith(tag):
        continue
    if stale.is_symlink() and stale.name.rsplit(".", 1)[-1] in {"pck", "wasm", "js"}:
        stale.unlink()
text = re.sub(r'"executable":"[^"]+"', f'"executable":"{tag}"', text, count=1)
text = re.sub(
    r'"fileSizes":\{[^}]+\}',
    f'"fileSizes":{{"{tag}.pck":{len(pck)},"{tag}.wasm":{wasm_size}}}',
    text,
    count=1,
)
text = re.sub(r'src="index\.js(?:\?[^"]*)?"', f'src="index.js?v={digest}"', text, count=1)
html_path.write_text(text)
print(f"web cache tag {tag}")
PY
