#!/bin/sh
# Stage build/web as build/site: the folder that is published (see README "Publishing").
set -eu
cd "$(dirname "$0")/.."

[ -f build/web/index.html ] || { echo "build/web/index.html is missing; run tools/build_web.sh first" >&2; exit 1; }

rm -rf build/site
# -L copies the cache-tagged symlinks as real files; a static host cannot follow them.
cp -RL build/web build/site

tag=$(sed -n 's/.*"executable":"\([^"]*\)".*/\1/p' build/site/index.html | head -n 1)
case "$tag" in
  g*) ;;
  *) echo "index.html has no cache-tagged executable name" >&2; exit 1 ;;
esac
for f in "$tag.pck" "$tag.wasm" "$tag.audio.worklet.js" "$tag.audio.position.worklet.js"; do
  [ -f "build/site/$f" ] || { echo "build/site/$f is missing" >&2; exit 1; }
done

# index.html loads only the tagged names, so the untagged copies are dead weight.
rm -f build/site/index.pck build/site/index.wasm build/site/index.audio.worklet.js build/site/index.audio.position.worklet.js
[ -f build/site/index.js ] || { echo "build/site/index.js is missing" >&2; exit 1; }

if [ -n "$(find build/site -type l)" ]; then
  echo "build/site still has symlinks" >&2; exit 1
fi
# GitHub's file limit is 100 MB; keeping under it keeps other hosts possible too.
if [ -n "$(find build/site -type f -size +100M)" ]; then
  echo "a file in build/site is over 100 MB" >&2; exit 1
fi

echo "staged build/site ($tag), $(du -sh build/site | cut -f1)"
