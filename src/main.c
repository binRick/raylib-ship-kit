// main.c - the entry point for desktop and browser. On iOS the app's main() lives in
// ios/KitBridge.m, which calls game_init / game_step / game_shutdown itself.
#include "kit.h"
#include "raylib.h"

#if defined(PLATFORM_IOS)
// nothing here: see ios/KitBridge.m

#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>

static int s_argc;
static char **s_argv;

// Called from JS once the saved files have been read back from IndexedDB.
EMSCRIPTEN_KEEPALIVE void kit_web_start(void) {
    game_init(s_argc, s_argv);
    EM_ASM({ window.dispatchEvent(new Event('resize')); });  // fill the page from the first frame
    emscripten_set_main_loop(game_step, 0, 0);  // the browser owns the loop
}

int main(int argc, char **argv) {
    s_argc = argc;
    s_argv = argv;
    EM_ASM({
        FS.mkdir('/save');
        FS.mount(IDBFS, {}, '/save');
        FS.syncfs(true, function (err) { if (err) console.warn('no saved data', err); _kit_web_start(); });
    });
    return 0;
}

#else
int main(int argc, char **argv) {
    game_init(argc, argv);
    while (!WindowShouldClose()) game_step();
    game_shutdown();
    return 0;
}
#endif
