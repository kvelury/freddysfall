#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
(sleep 0.4 && open "http://localhost:8060") &
exec python3 -m http.server 8060 -d build/web
