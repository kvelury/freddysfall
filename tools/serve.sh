#!/bin/sh
# Usage: tools/serve.sh [web|site]   (site is the staged copy from tools/stage_site.sh)
set -eu
cd "$(dirname "$0")/.."
(sleep 0.4 && open "http://localhost:8060") &
exec python3 -m http.server 8060 -d "build/${1:-web}"
