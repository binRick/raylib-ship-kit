#!/usr/bin/env bash
# install-raylib-ios.sh
#
# Patches vendor/raylib-src so it can build for iOS:
#   1. Copies ios/rcore_ios.c into vendor/raylib-src/src/platforms/
#   2. Adds a `#elif defined(PLATFORM_IOS)` branch in rcore.c so the
#      platform dispatch picks up our module.
#
# Idempotent - running twice is a no-op. Clones raylib (RAYLIB_TAG in kit.env) into
# vendor/raylib-src the first time.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
vendor="$repo/vendor/raylib-src/src"

# A separate raylib clone for iOS, so the desktop build's copy (build/_deps) is never patched.
. "$repo/kit.env"
if [[ ! -f "$vendor/rcore.c" ]]; then
    git clone --depth 1 --branch "$RAYLIB_TAG" https://github.com/raysan5/raylib.git "$repo/vendor/raylib-src"
fi

# 1) Copy our platform module into raylib's platforms/ directory.
cp "$repo/ios/rcore_ios.c" "$vendor/platforms/rcore_ios.c"
echo "Copied rcore_ios.c -> $vendor/platforms/"

# 2) Patch rcore.c to add the PLATFORM_IOS dispatch branch (if not already there).
# raylib 6.x's rcore.c references PLATFORM_MEMORY in TWO places: the module-
# scope platform-include switch (~line 553) AND inside InitWindow()'s banner-
# log switch (~line 631). We must insert our branch ONLY at the first hit;
# inserting at the InitWindow site puts an `#include "platforms/rcore_ios.c"`
# inside a function body and fails with "function definition is not allowed
# here". Bump the once-only counter if upstream restructures rcore.c.
if grep -q 'PLATFORM_IOS' "$vendor/rcore.c"; then
    echo "rcore.c already patched - skipping."
else
    tmp="$(mktemp)"
    awk '
        /^#elif defined\(PLATFORM_MEMORY\)/ && !done {
            print "#elif defined(PLATFORM_IOS)"
            print "    #include \"platforms/rcore_ios.c\""
            done = 1
        }
        { print }
    ' "$vendor/rcore.c" > "$tmp"
    mv "$tmp" "$vendor/rcore.c"
    echo "Patched rcore.c with PLATFORM_IOS dispatch branch (module scope only)."
fi

# 3) Patch rlgl.h: on Apple platforms the GLES3 header lives at
#    <OpenGLES/ES3/gl.h>, not <GLES3/gl3.h>. We splice an Apple branch into
#    the existing GRAPHICS_API_OPENGL_ES3 include block.
if grep -q 'OpenGLES/ES3/gl.h' "$vendor/rlgl.h"; then
    echo "rlgl.h already patched - skipping."
else
    tmp="$(mktemp)"
    awk '
        /^    #include <GLES3\/gl3.h>/ && !done {
            print "  #if defined(__APPLE__)"
            print "    #include <OpenGLES/ES3/gl.h>"
            print "    #include <OpenGLES/ES3/glext.h>"
            print "  #else"
            print "    #include <GLES3/gl3.h>              // OpenGL ES 3.0 library"
            print "    #define GL_GLEXT_PROTOTYPES"
            print "    #include <GLES2/gl2ext.h>           // OpenGL ES 2.0 extensions library"
            print "  #endif"
            done = 1
            # Skip the next two lines (the original GLES3 + GL_GLEXT_PROTOTYPES + gl2ext)
            getline; getline
            next
        }
        { print }
    ' "$vendor/rlgl.h" > "$tmp"
    mv "$tmp" "$vendor/rlgl.h"
    echo "Patched rlgl.h to use OpenGLES/ES3 on Apple."
fi

# 4) Patch rlDisableFramebuffer to bind our iOS default FBO instead of 0.
#    On iOS the screen-backing framebuffer is whatever id glGenFramebuffers
#    returned in the bridge - never 0. raylib's EndTextureMode + similar
#    "return to screen" sites all call rlDisableFramebuffer, so one patch
#    site covers the lot.
if grep -q 'KitRcoreGetDefaultFbo' "$vendor/rlgl.h"; then
    echo "rlgl.h rlDisableFramebuffer already patched - skipping."
else
    tmp="$(mktemp)"
    # Guard with PLATFORM_IOS, NOT __APPLE__: macOS also defines __APPLE__
    # and gets compiled with this same patched header, but never defines
    # KitRcoreGetDefaultFbo - so __APPLE__ produced unresolved-symbol
    # errors at the macOS link stage.
    awk '
        BEGIN { in_dis = 0; patched = 0 }
        /^void rlDisableFramebuffer\(void\)/ { in_dis = 1 }
        in_dis && /glBindFramebuffer\(GL_FRAMEBUFFER, 0\);/ && !patched {
            print "#if defined(PLATFORM_IOS)"
            print "    extern unsigned int KitRcoreGetDefaultFbo(void);"
            print "    glBindFramebuffer(GL_FRAMEBUFFER, KitRcoreGetDefaultFbo());"
            print "#else"
            print $0
            print "#endif"
            patched = 1
            next
        }
        /^}/ && in_dis { in_dis = 0 }
        { print }
    ' "$vendor/rlgl.h" > "$tmp"
    mv "$tmp" "$vendor/rlgl.h"
    echo "Patched rlDisableFramebuffer to use iOS default FBO."
fi

echo "raylib source ready for iOS."
