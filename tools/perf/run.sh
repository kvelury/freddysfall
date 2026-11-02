#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
perf_tmp=$(mktemp -d)
trap 'rm -rf "$perf_tmp"' EXIT HUP INT TERM
export PERF_CACHE_ROOT="$perf_tmp/solver"
export XDG_DATA_HOME="$perf_tmp/data"
export XDG_CONFIG_HOME="$perf_tmp/config"
export XDG_CACHE_HOME="$perf_tmp/cache"
printf 'commit %s\n' "$(git rev-parse HEAD)"
printf 'machine '; uname -sm
cat /sys/fs/cgroup/cpu.max 2>/dev/null || true
timeout 120 "${GODOT:-godot}" --headless --path . --import >/dev/null
timeout 120 "${GODOT:-godot}" --headless --path . --script tools/perf/profile.gd
