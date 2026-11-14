#!/usr/bin/env bash
# Build the browser version (WebAssembly + WebGL 2) into dist/web/.
#   scripts/build-web.sh           build only
#   scripts/build-web.sh --serve   build, then serve it at http://127.0.0.1:8080/
# Needs emscripten (brew install emscripten, or emsdk). Host dist/web/ anywhere static.
. "$(dirname "$0")/_kit.sh"
need emcmake "brew install emscripten"

# Homebrew's emcc needs Python 3.10+, which Xcode's python3 (3.9) shadows on macOS.
if [[ -z "${EMCC_PYTHON:-}" && -d /opt/homebrew/bin ]]; then
    py="$(ls /opt/homebrew/bin/python3.1[0-9] 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "$py" ]] && export EMCC_PYTHON="$py" EMSDK_PYTHON="$py"
fi

[[ -f build-web/CMakeCache.txt ]] || emcmake cmake -S . -B build-web -DCMAKE_BUILD_TYPE=Release
cmake --build build-web -j "$JOBS"

rm -rf dist/web && mkdir -p dist/web
cp build-web/index.{html,js,wasm,data} dist/web/
# the page title comes from kit.env
sed -i.bak "s/__APP_NAME__/$APP_NAME/" dist/web/index.html && rm dist/web/index.html.bak
du -sh dist/web

if [[ "${1:-}" == "--serve" ]]; then
    echo "Serving http://127.0.0.1:8080/ (Ctrl-C to stop)"
    cd dist/web && exec python3 -m http.server 8080 --bind 127.0.0.1
fi
