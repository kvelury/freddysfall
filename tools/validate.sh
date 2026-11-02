#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# A new class_name is not visible to a script run until the project is imported.
python3 tools/test_runner.py import
exec python3 tools/test_runner.py validate "$@"
