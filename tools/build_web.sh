#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
godot --headless --path . --import
mkdir -p build/web
godot --headless --path . --export-release "Web" "build/web/index.html"
python3 - << 'PY'
from pathlib import Path
path = Path("build/web/index.html")
text = path.read_text()
snippet = "<script>window.addEventListener('keydown',function(e){if(e.key==='Tab')e.preventDefault();},true);</script>"
if "e.key==='Tab'" not in text:
    text = text.replace("</head>", snippet + "\n</head>", 1)
    path.write_text(text)
PY
