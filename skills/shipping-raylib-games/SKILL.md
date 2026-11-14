---
name: shipping-raylib-games
description: Use when building, packaging or releasing a raylib C game with raylib-ship-kit (a repo with kit.env, src/kit.h and scripts/ios-sim.sh), when porting an existing raylib game onto the kit, or when a raylib game must run on iOS, in the browser (emscripten), or go to the App Store - including symptoms like a black screen on iOS, taps not registering, assets not found in a packaged build, or saves lost on browser reload.
---

# Shipping raylib games with raylib-ship-kit

The kit builds one raylib C codebase for macOS, Windows, Linux, browser and iOS. The game
implements three functions; per-platform entry points drive them. Never give a kit game its
own top-level loop.

## The contract

```c
#include "kit.h"
void game_init(int argc, char **argv);  // InitWindow, InitAudioDevice, kit_init(), load assets
void game_step(void);                   // ONE frame: update, BeginDrawing..EndDrawing
void game_shutdown(void);               // unload, CloseAudioDevice, CloseWindow
```

- `src/main.c` owns `main()` on desktop and browser; `ios/KitBridge.m` owns it on iOS. Game
  files define no `main()` and no `while (!WindowShouldClose())`.
- Loop-local variables of the old `main()` become file-scope `static`s.
- Call `kit_init()` once, after `InitWindow` (and `InitAudioDevice`), before loading anything.
  After it, `"assets/..."` paths resolve on every platform.
- Every file the game writes goes through `kit_save_path("name")`, followed by
  `kit_save_flush()`. A bare relative path works on a dev machine and fails inside a signed
  `.app`, on iOS (read-only bundle) and in the browser (lost on reload).

## Porting an existing game

1. `kit.env`: set `APP_NAME`, `APP_SLUG` (lowercase, no spaces), `BUNDLE_ID`. Nothing else
   holds a name: do not edit `ios/project.yml`, `Info.plist`, `CMakeLists.txt` or the scripts
   to rename things.
2. Delete `src/game.c`; add the game's `.c`/`.h` files to `src/` (globbed automatically by
   CMake and Xcode). Keep `src/kit.c`, `src/kit.h`, `src/main.c`.
3. Split the old `main()` into the three functions as above.
4. Move data files into `assets/` and change load paths to `assets/...`. The folder name is
   fixed: the web preload, the iOS copy phase and the packagers all ship `assets/`.
5. Replace `fopen("save.dat")`-style paths with `kit_save_path(...)` + `kit_save_flush()`.
6. Replace `assets/icon.png` (1024px square, no alpha needed in the source; see
   `scripts/gen-assets.py` for how the iOS and `.ico` variants are cut).
7. Do not hard-code the window size in layout maths: on iOS and in the browser
   `GetScreenWidth()/GetScreenHeight()` are whatever the device gives, regardless of the size
   passed to `InitWindow`. Scale from them each frame.
8. Input: touch slot 0 drives raylib's mouse on iOS and the browser, so
   `IsMouseButtonPressed/Down` + `GetMousePosition` already work for one finger. A game that is
   keyboard-only needs an on-screen or pointer alternative before it is playable on a phone.

## Commands

Run from the repo root. Each script prints what it needs if a tool is missing.

| Goal | Command | Output |
|---|---|---|
| Build + run on this machine | `./run.sh [game args]` | `build/<slug>` |
| Browser | `bash scripts/build-web.sh [--serve]` | `dist/web/` |
| Windows (cross) | `bash scripts/build-windows.sh` | `dist/<slug>-windows.zip` |
| Linux package | `bash scripts/build-linux.sh` (on Linux) | `dist/<slug>-linux-<arch>.tar.gz` |
| macOS app, no Apple account | `bash scripts/mac-release.sh --adhoc` | `dist/<slug>-macos.zip` |
| macOS notarized release | `NOTARY_PROFILE=<p> bash scripts/mac-release.sh` | same, stapled |
| iOS simulator | `bash scripts/ios-sim.sh [-- game args]` | launched app |
| iOS device | `TEAM_ID=<id> bash scripts/ios-device.sh` | launched app |
| App Store upload | `TEAM_ID=.. ASC_KEY_ID=.. ASC_ISSUER_ID=.. bash scripts/ios-appstore.sh` | uploaded build |
| Submit for review | `python3 scripts/asc-submit.py "What's new"` | review submission |

Verify a build by looking at it, not by its exit code:
`xcrun simctl io booted screenshot shot.png` for the simulator; open `dist/web/` through a
local server (not `file://`) for the browser.

## Before a release

- Bump `VERSION`. Apple rejects an upload whose version it has already seen.
- Uploading, submitting for review and notarizing act on the user's Apple account. Confirm
  with the user before running `ios-appstore.sh` (without `DRY_RUN=1`), `asc-submit.py` or a
  non-`--adhoc` `mac-release.sh`. Never invent or guess `TEAM_ID`, key ids or bundle ids.
- The first version of a new app needs its listing, screenshots and privacy answers entered
  on appstoreconnect.apple.com; `asc-submit.py` copies them forward from then on.

## Symptoms

| Symptom | Cause / fix |
|---|---|
| `emscripten requires python 3.10` | Use `scripts/build-web.sh`, which sets `EMCC_PYTHON`; do not call `emcmake` directly on macOS |
| Browser page loads, canvas stays blank, console shows a missing file | Asset is outside `assets/`, or the path is not `assets/...` |
| Browser build hangs at start | Something blocks in `game_init` (a `while` loop, `WaitTime`); the browser needs `game_step` to return every frame |
| Saves gone after browser reload | `kit_save_flush()` not called after writing |
| iOS: "Failed to open file" for a save | Writing next to the executable; use `kit_save_path` |
| iOS: black screen after `EndTextureMode` | raylib clone not patched: run `bash ios/install-raylib-ios.sh`, then rebuild raylib with `bash ios/build-raylib.sh both` |
| iOS: link error `library 'raylib' not found` | `vendor-ios/lib-iphoneos` or `lib-iphonesimulator` missing: `bash ios/build-raylib.sh both` |
| iOS build uses old name or version | The Xcode project is generated from `kit.env`/`VERSION`; rerun the script, never edit `ios/Game.xcodeproj` |
| Changed `RAYLIB_TAG`, iOS still on the old raylib | Delete `vendor/raylib-src` and `vendor-ios`, rerun |
| Windows `.exe` shows a console or needs DLLs | Built without the kit's CMake flags; use `scripts/build-windows.sh` |
| `xcodegen: command not found` | `brew install xcodegen` |

## Common mistakes

- Keeping a `while (!WindowShouldClose())` loop "just for desktop" behind `#ifdef`s. One
  `game_step()` for all platforms is the point; `src/main.c` already loops it on desktop.
- Committing `ios/Game.xcodeproj`, `vendor/`, `vendor-ios/`, `build*/` or `dist/`. All are
  generated and git-ignored.
- Calling `exit()` or `CloseWindow()` from `game_step` on iOS or the browser to "quit". Those
  platforms have no quit; hide the option there (`#if defined(PLATFORM_IOS) || defined(__EMSCRIPTEN__)`).
- Using `TakeScreenshot()` on a HiDPI Mac: it captures 4x the window. Read the framebuffer as
  `src/game.c`'s `--shot` does.
