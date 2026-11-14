#!/usr/bin/env bash
# Build on Linux and package dist/<slug>-linux-<arch>.tar.gz (the binary beside assets/).
# Needs: build-essential cmake git libasound2-dev libx11-dev libxrandr-dev libxi-dev
#        libgl1-mesa-dev libglu1-mesa-dev libxcursor-dev libxinerama-dev libwayland-dev libxkbcommon-dev
. "$(dirname "$0")/_kit.sh"
[[ "$(uname -s)" == Linux ]] || die "run this on Linux (CI does: see .gitlab-ci.yml)"

[[ -f build-linux/CMakeCache.txt ]] || cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release
cmake --build build-linux -j "$JOBS"

stage="build-linux/$APP_SLUG"
rm -rf "$stage" && mkdir -p "$stage"
cp "build-linux/$APP_SLUG" "$stage/"
cp -R assets "$stage/"
mkdir -p dist
tar -C build-linux -czf "dist/$APP_SLUG-linux-$(uname -m).tar.gz" "$APP_SLUG"
ls -la dist/*.tar.gz
