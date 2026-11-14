#!/usr/bin/env bash
# Build for this machine (macOS or Linux) and run. Arguments go to the game.
set -euo pipefail
cd "$(dirname "$0")"
. ./kit.env
cmake -S . -B build -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-Debug}" > /dev/null
cmake --build build -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
exec "./build/$APP_SLUG" "$@"
