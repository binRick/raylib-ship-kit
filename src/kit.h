// kit.h - the few things that differ per platform, behind one small API.
#ifndef KIT_H
#define KIT_H

// Call once before InitWindow. Makes "assets/..." resolve on every platform
// (repo checkout, macOS .app, Windows zip, iOS bundle, browser) and creates the save folder.
void kit_init(void);

// A writable path for `file`: Application Support on macOS, %APPDATA% on Windows,
// XDG data dir on Linux, Documents on iOS, IndexedDB-backed /save in the browser.
const char *kit_save_path(const char *file);

// Call after writing a save. A no-op everywhere except the browser, where it persists /save.
void kit_save_flush(void);

// iOS only: the bridge hands over the Documents folder before game_init().
void kit_set_save_dir(const char *dir);

// Your game. main.c, the iOS bridge and the browser loop all drive these three.
void game_init(int argc, char **argv);
void game_step(void);       // exactly one frame: update + draw
void game_shutdown(void);

#endif
