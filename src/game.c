// game.c - Star Catcher, the demo that proves the pipeline. Replace it with your game:
// keep the three entry points (game_init / game_step / game_shutdown) and everything in
// scripts/ keeps working.
//
// It is deliberately small but touches what a real game needs on every platform: pointer
// input that works for mouse and finger, keyboard, a bundled sound, and a saved high score.
#include "kit.h"
#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef KIT_APP_NAME
#define KIT_APP_NAME "Star Catcher"
#endif

#define MAX_ITEMS 40
#define MAX_SPARKS 160

typedef struct { Vector2 pos, vel; float rot, spin; int kind; bool live; } Item;  // kind 0 star, 1 mine
typedef struct { Vector2 pos, vel; float life; Color col; } Spark;
typedef enum { TITLE, PLAY, OVER } Mode;

static Item items[MAX_ITEMS];
static Spark sparks[MAX_SPARKS];
static Mode mode = TITLE;
static float ship_x = 0.5f;   // 0..1 across the screen
static float spawn_in, t_total, shake;
static int score, best, lives;
static Sound snd_catch, snd_hit;
static const char *shot_path;  // --shot <file>: play itself, save a screenshot, quit
static int frame_no;  // counts frames for --shot

static const Color SKY_TOP = { 13, 16, 38, 255 }, SKY_BOT = { 46, 28, 84, 255 };
static const Color STARCOL = { 255, 205, 80, 255 }, MINE = { 240, 84, 104, 255 }, HULL = { 120, 225, 235, 255 };

static float unit(void) { return GetScreenHeight() / 720.0f; }  // everything is sized in 720p units

static void draw_star(Vector2 c, float r, float rot, Color col) {
    Vector2 v[11];
    for (int i = 0; i <= 10; i++) {
        float a = rot + i * PI / 5.0f, rr = (i % 2) ? r * 0.45f : r;
        v[i] = (Vector2){ c.x + sinf(a) * rr, c.y - cosf(a) * rr };
    }
    for (int i = 0; i < 10; i++) { DrawTriangle(c, v[i], v[i + 1], col); DrawTriangle(c, v[i + 1], v[i], col); }
}

static void burst(Vector2 at, Color col, int n) {
    for (int i = 0; i < MAX_SPARKS && n > 0; i++) {
        if (sparks[i].life > 0) continue;
        float a = GetRandomValue(0, 628) / 100.0f, s = GetRandomValue(80, 420) * unit();
        sparks[i] = (Spark){ at, { cosf(a) * s, sinf(a) * s }, 0.7f, col };
        n--;
    }
}

static void start_run(void) {
    memset(items, 0, sizeof items);
    score = 0; lives = 3; spawn_in = 0.4f; mode = PLAY;
}

static void end_run(void) {
    mode = OVER;
    if (score > best) {
        best = score;
        SaveFileText(kit_save_path("best.txt"), TextFormat("%d\n", best));
        kit_save_flush();
    }
}

void game_init(int argc, char **argv) {
    for (int i = 1; i + 1 < argc; i++) if (!strcmp(argv[i], "--shot")) shot_path = argv[i + 1];

    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT | FLAG_MSAA_4X_HINT | FLAG_WINDOW_HIGHDPI);
    InitWindow(1280, 720, KIT_APP_NAME);
    SetWindowMinSize(480, 270);
    SetTargetFPS(60);
    InitAudioDevice();
    kit_init();

    snd_catch = LoadSound("assets/catch.wav");
    snd_hit = LoadSound("assets/hit.wav");
    char *saved = LoadFileText(kit_save_path("best.txt"));
    if (saved) { sscanf(saved, "%d", &best); UnloadFileText(saved); }
    if (shot_path) { SetRandomSeed(7); SetMasterVolume(0); start_run(); score = 12; best = 31; }
}

static void update(float dt) {
    float w = GetScreenWidth(), h = GetScreenHeight(), u = unit();
    bool tap = IsMouseButtonPressed(MOUSE_BUTTON_LEFT) || IsKeyPressed(KEY_SPACE) || IsKeyPressed(KEY_ENTER);
    t_total += dt;
    shake = fmaxf(0, shake - dt * 3);

    for (int i = 0; i < MAX_SPARKS; i++) {
        if (sparks[i].life <= 0) continue;
        sparks[i].life -= dt;
        sparks[i].pos = Vector2Add(sparks[i].pos, Vector2Scale(sparks[i].vel, dt));
        sparks[i].vel.y += 600 * u * dt;
    }
    if (mode != PLAY) { if (tap) start_run(); return; }

    // One finger, the mouse, or the arrow keys: all three steer.
    if (IsMouseButtonDown(MOUSE_BUTTON_LEFT)) ship_x = Lerp(ship_x, GetMouseX() / w, fminf(1, dt * 14));
    if (IsKeyDown(KEY_LEFT) || IsKeyDown(KEY_A)) ship_x -= dt * 1.1f;
    if (IsKeyDown(KEY_RIGHT) || IsKeyDown(KEY_D)) ship_x += dt * 1.1f;
    if (shot_path) {  // autopilot for the screenshot: chase the lowest star
        float want = ship_x, low = -1;
        for (int i = 0; i < MAX_ITEMS; i++)
            if (items[i].live && items[i].kind == 0 && items[i].pos.y > low) { low = items[i].pos.y; want = items[i].pos.x / w; }
        ship_x = Lerp(ship_x, want, dt * 6);
    }
    ship_x = Clamp(ship_x, 0.04f, 0.96f);

    spawn_in -= dt;
    if (spawn_in <= 0) {
        spawn_in = fmaxf(0.16f, 0.55f - score * 0.006f);
        for (int i = 0; i < MAX_ITEMS; i++) {
            if (items[i].live) continue;
            items[i] = (Item){ { GetRandomValue(40, (int)w - 40), -40 * u }, { 0, GetRandomValue(220, 380) * u + score * 2 * u },
                               0, GetRandomValue(-30, 30) / 10.0f, GetRandomValue(0, 99) < 30, true };
            break;
        }
    }
    Vector2 ship = { ship_x * w, h - 90 * u };
    for (int i = 0; i < MAX_ITEMS; i++) {
        Item *it = &items[i];
        if (!it->live) continue;
        it->pos.y += it->vel.y * dt;
        it->rot += it->spin * dt;
        if (it->pos.y > h + 60 * u) { it->live = false; continue; }
        if (Vector2Distance(it->pos, ship) > 58 * u) continue;
        it->live = false;
        if (it->kind == 0) { score++; burst(it->pos, STARCOL, 14); PlaySound(snd_catch); }
        else { lives--; shake = 1; burst(it->pos, MINE, 30); PlaySound(snd_hit); if (lives <= 0) end_run(); }
    }
}

static void centered(const char *text, float y, float size, Color col) {
    DrawText(text, (GetScreenWidth() - MeasureText(text, (int)size)) / 2, (int)y, (int)size, col);
}

static void draw(void) {
    float w = GetScreenWidth(), h = GetScreenHeight(), u = unit();
    BeginDrawing();
    DrawRectangleGradientV(0, 0, (int)w, (int)h, SKY_TOP, SKY_BOT);
    for (int i = 0; i < 90; i++) {  // a cheap twinkling backdrop, no assets
        float x = fmodf(i * 197.3f, 1.0f) * w + fmodf(i * 0.37f, 1.0f) * w;
        float y = fmodf(i * 0.6180339f, 1.0f) * h + t_total * (6 + i % 5 * 5) * u;
        float tw = 0.45f + 0.35f * sinf(t_total * 2 + i);
        DrawCircleV((Vector2){ fmodf(x, w), fmodf(y, h) }, (1 + i % 3) * 0.9f * u, Fade(WHITE, tw));
    }

    Vector2 off = { sinf(t_total * 90) * shake * 10 * u, cosf(t_total * 70) * shake * 10 * u };
    for (int i = 0; i < MAX_ITEMS; i++) {
        if (!items[i].live) continue;
        Vector2 p = Vector2Add(items[i].pos, off);
        if (items[i].kind == 0) { DrawCircleV(p, 34 * u, Fade(STARCOL, 0.12f)); draw_star(p, 24 * u, items[i].rot, STARCOL); }
        else { DrawPoly(p, 8, 26 * u, items[i].rot * 40, Fade(MINE, 0.35f)); DrawPoly(p, 4, 22 * u, items[i].rot * 60, MINE);
               DrawPoly(p, 4, 22 * u, items[i].rot * 60 + 45, MINE); DrawCircleV(p, 9 * u, SKY_TOP); }
    }
    for (int i = 0; i < MAX_SPARKS; i++)
        if (sparks[i].life > 0) DrawCircleV(sparks[i].pos, 4 * u * sparks[i].life * 1.6f, Fade(sparks[i].col, sparks[i].life));

    if (mode == PLAY) {
        Vector2 s = Vector2Add((Vector2){ ship_x * w, h - 90 * u }, off);
        float fl = (18 + 8 * sinf(t_total * 40)) * u;
        DrawTriangle((Vector2){ s.x - 12 * u, s.y + 26 * u }, (Vector2){ s.x, s.y + 26 * u + fl * 2 }, (Vector2){ s.x + 12 * u, s.y + 26 * u }, STARCOL);
        DrawTriangle((Vector2){ s.x, s.y - 44 * u }, (Vector2){ s.x - 30 * u, s.y + 28 * u }, (Vector2){ s.x + 30 * u, s.y + 28 * u }, HULL);
        DrawTriangle((Vector2){ s.x, s.y - 14 * u }, (Vector2){ s.x - 12 * u, s.y + 16 * u }, (Vector2){ s.x + 12 * u, s.y + 16 * u }, SKY_TOP);
    }

    // HUD
    draw_star((Vector2){ 44 * u, 46 * u }, 18 * u, 0, STARCOL);
    DrawText(TextFormat("%d", score), (int)(72 * u), (int)(26 * u), (int)(40 * u), WHITE);
    const char *b = TextFormat("BEST %d", best);
    DrawText(b, (int)(w - MeasureText(b, (int)(26 * u)) - 28 * u), (int)(32 * u), (int)(26 * u), Fade(WHITE, 0.7f));
    for (int i = 0; i < lives && mode == PLAY; i++) {
        float x = w / 2 + (i - 1) * 34 * u;
        DrawTriangle((Vector2){ x, 28 * u }, (Vector2){ x - 11 * u, 56 * u }, (Vector2){ x + 11 * u, 56 * u }, HULL);
    }
    if (mode != PLAY) {
        DrawRectangle(0, 0, (int)w, (int)h, Fade(SKY_TOP, 0.55f));
        centered(mode == TITLE ? "STAR CATCHER" : "GAME OVER", h * 0.30f, 84 * u, WHITE);
        centered(mode == TITLE ? "catch the stars, dodge the mines" : TextFormat("%d stars", score), h * 0.30f + 100 * u, 32 * u, STARCOL);
        if (fmodf(t_total, 1.2f) < 0.8f) centered("tap, click or press SPACE", h * 0.66f, 28 * u, Fade(WHITE, 0.85f));
    }
    EndDrawing();
}

void game_step(void) {
    update(shot_path ? 1 / 60.0f : fminf(GetFrameTime(), 0.05f));
    draw();
#ifndef PLATFORM_IOS
    if (shot_path && ++frame_no == 260) {
        // not TakeScreenshot(): on a HiDPI screen raylib scales the already-scaled size and reads 4x the window
        Image img = { rlReadScreenPixels(GetRenderWidth(), GetRenderHeight()), GetRenderWidth(), GetRenderHeight(), 1,
                      PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };
        ExportImage(img, shot_path);
        CloseWindow();
        exit(0);
    }
#endif
}

void game_shutdown(void) {
    UnloadSound(snd_catch);
    UnloadSound(snd_hit);
    CloseAudioDevice();
    CloseWindow();
}
