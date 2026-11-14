#!/usr/bin/env bash
# build-raylib.sh [sim|device|both]
#
# Cross-compile raylib core into a static lib for one or both iOS targets.
# Output:
#   vendor-ios/lib-iphonesimulator/libraylib.a (arm64 simulator)
#   vendor-ios/lib-iphoneos/libraylib.a        (arm64 device)
#   vendor-ios/include/{raylib,raymath,rlgl,rcamera}.h
#
# Run after install-raylib-ios.sh has stamped rcore_ios.c into vendor/raylib-src.
# Re-run if you bump raylib or change rcore_ios.c. Default target is "sim" so
# the simulator pipeline keeps working without arguments.

set -euo pipefail

mode="${1:-sim}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
vendor="$repo/vendor/raylib-src/src"
out="$repo/vendor-ios"

# Make sure rcore.c carries the PLATFORM_IOS branch + rcore_ios.c is in place.
"$repo/ios/install-raylib-ios.sh"

if ! command -v xcrun >/dev/null; then
    echo "ERROR: xcrun not on PATH. Install Xcode + accept the license." >&2
    exit 1
fi

MIN_IOS=16.0
ARCH=arm64

# build_for <sim|device>
build_for() {
    local target="$1"
    local sdk_name target_triple min_flag obj_dir lib_dir
    if [[ "$target" == "sim" ]]; then
        sdk_name=iphonesimulator
        target_triple="${ARCH}-apple-ios${MIN_IOS}-simulator"
        min_flag="-mios-simulator-version-min=$MIN_IOS"
        obj_dir="$out/obj-sim"
        lib_dir="$out/lib-iphonesimulator"
    else
        sdk_name=iphoneos
        target_triple="${ARCH}-apple-ios${MIN_IOS}"
        min_flag="-miphoneos-version-min=$MIN_IOS"
        obj_dir="$out/obj-device"
        lib_dir="$out/lib-iphoneos"
    fi

    echo "==> Building libraylib.a for $target ($target_triple)"

    local SDK CC
    SDK="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
    CC=$(xcrun --sdk "$sdk_name" --find clang)

    local CFLAGS=(
        -arch $ARCH
        -isysroot "$SDK"
        -target "$target_triple"
        $min_flag
        -O2 -fPIC
        -Wno-implicit-function-declaration
        -Wno-deprecated-declarations
        -DPLATFORM_IOS
        -DGRAPHICS_API_OPENGL_ES3
        -DSUPPORT_MODULE_RSHAPES
        -DSUPPORT_MODULE_RTEXTURES
        -DSUPPORT_MODULE_RTEXT
        -DSUPPORT_MODULE_RMODELS
        -DSUPPORT_MODULE_RAUDIO
        -DSUPPORT_FILEFORMAT_PNG
        -DSUPPORT_FILEFORMAT_JPG
        -DSUPPORT_FILEFORMAT_OBJ
        -DSUPPORT_FILEFORMAT_MTL
        -DSUPPORT_FILEFORMAT_WAV
        -DSUPPORT_FILEFORMAT_OGG
        -DSUPPORT_FILEFORMAT_MP3
        -DSUPPORT_FILEFORMAT_GLTF
        -DSUPPORT_FILEFORMAT_TTF
        -I"$vendor"
        # Do NOT add -I"$vendor/external": its Win32 dirent.h polyfill would
        # shadow the iOS system header.
        -include "$repo/ios/raylib_ios_glcompat.h"
    )

    rm -rf "$obj_dir"
    mkdir -p "$obj_dir" "$lib_dir" "$out/include"

    # rglfw.c is desktop-only - skip it on iOS.
    local modules=(rcore rshapes rtextures rtext rmodels raudio)

    for m in "${modules[@]}"; do
        local src="$vendor/$m.c"
        local obj_file="$obj_dir/$m.o"
        if [[ "$m" == "raudio" ]]; then
            # miniaudio's Apple backend pulls AVFoundation, which is ObjC-only.
            echo "  CC  $m.c (objective-c)"
            "$CC" "${CFLAGS[@]}" -x objective-c -fobjc-arc -fmodules -c "$src" -o "$obj_file"
        else
            echo "  CC  $m.c"
            "$CC" "${CFLAGS[@]}" -c "$src" -o "$obj_file"
        fi
    done

    echo "  AR  $lib_dir/libraylib.a"
    ar rcs "$lib_dir/libraylib.a" "$obj_dir"/*.o
    ranlib "$lib_dir/libraylib.a"
    ls -la "$lib_dir/libraylib.a"
}

case "$mode" in
    sim)    build_for sim ;;
    device) build_for device ;;
    both)   build_for sim; build_for device ;;
    *)      echo "Usage: $0 [sim|device|both]" >&2; exit 2 ;;
esac

# Public headers - same for both targets.
cp "$vendor/raylib.h"  "$out/include/"
cp "$vendor/raymath.h" "$out/include/"
cp "$vendor/rlgl.h"    "$out/include/"
cp "$vendor/rcamera.h" "$out/include/" 2>/dev/null || true

echo
echo "Done. Headers: $out/include/"
