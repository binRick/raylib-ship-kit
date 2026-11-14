#!/usr/bin/env bash
# Cross-compile the Windows build from macOS or Linux and zip it: dist/<slug>-windows.zip
# holds one self-contained .exe (icon, version info, DPI-aware manifest) beside assets/.
# Needs mingw-w64 (brew install mingw-w64 / apt install mingw-w64).
. "$(dirname "$0")/_kit.sh"
need x86_64-w64-mingw32-gcc "brew install mingw-w64"

[[ -f build-win/CMakeCache.txt ]] || cmake -S . -B build-win -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64.cmake
cmake --build build-win -j "$JOBS"

stage="build-win/$APP_SLUG"
rm -rf "$stage" && mkdir -p "$stage"
cp "build-win/$APP_SLUG.exe" "$stage/"
cp -R assets "$stage/"
mkdir -p dist && rm -f "dist/$APP_SLUG-windows.zip"
(cd build-win && zip -qr "../dist/$APP_SLUG-windows.zip" "$APP_SLUG")
ls -la "dist/$APP_SLUG-windows.zip"
