// kit.c - asset lookup and save paths for every platform the kit ships to.
#include "kit.h"
#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

#ifndef KIT_APP_NAME
#define KIT_APP_NAME "game"
#endif

static char s_save_dir[1024];

void kit_set_save_dir(const char *dir) { snprintf(s_save_dir, sizeof s_save_dir, "%s", dir); }

static void pick_save_dir(void) {
    if (s_save_dir[0]) return;  // iOS: already set by the bridge
#if defined(__EMSCRIPTEN__)
    kit_set_save_dir("/save");  // mounted on IndexedDB by main.c
#elif defined(_WIN32)
    const char *base = getenv("APPDATA");
    snprintf(s_save_dir, sizeof s_save_dir, "%s\\%s", base ? base : ".", KIT_APP_NAME);
#elif defined(__APPLE__)
    const char *home = getenv("HOME");
    snprintf(s_save_dir, sizeof s_save_dir, "%s/Library/Application Support/%s", home ? home : ".", KIT_APP_NAME);
#else
    const char *xdg = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
    if (xdg && xdg[0]) snprintf(s_save_dir, sizeof s_save_dir, "%s/%s", xdg, KIT_APP_NAME);
    else snprintf(s_save_dir, sizeof s_save_dir, "%s/.local/share/%s", home ? home : ".", KIT_APP_NAME);
#endif
}

void kit_init(void) {
    pick_save_dir();
#ifndef __EMSCRIPTEN__
    // Find assets/ next to the executable (zip, iOS bundle), one level up (build/ in a
    // checkout) or in ../Resources (macOS .app), then work from there.
    const char *exe = GetApplicationDirectory();
    const char *tries[] = { "", "../", "../Resources/" };
    for (int i = 0; i < 3; i++) {
        const char *dir = TextFormat("%s%s", exe, tries[i]);
        if (DirectoryExists(TextFormat("%sassets", dir))) { ChangeDirectory(dir); break; }
    }
#endif
    MakeDirectory(s_save_dir);
}

const char *kit_save_path(const char *file) {
    static char path[1280];
    snprintf(path, sizeof path, "%s/%s", s_save_dir, file);
    return path;
}

void kit_save_flush(void) {
#ifdef __EMSCRIPTEN__
    EM_ASM({ FS.syncfs(false, function (err) { if (err) console.warn('save failed', err); }); });
#endif
}
