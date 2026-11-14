/**********************************************************************************************
*
*   rcore_ios - raylib core platform layer for iOS (UIKit + GLES3)
*
*   The GLES context, the CAEAGLLayer-backed framebuffer, the CADisplayLink that
*   drives game_step(), and all touch dispatch live in ios/KitBridge.m. This file
*   owns CORE.Window / CORE.Input / CORE.Time bookkeeping and the small handful of
*   per-frame plumbing functions raylib expects from a platform module.
*
*   Bridge -> rcore handoff:
*     - Bridge calls KitRcoreSetScreenSize(w, h) BEFORE the game's main()
*       runs InitWindow. InitWindow's width/height args still get used (they
*       become CORE.Window.screen), so the values must match.
*     - Bridge calls KitRcoreSetFbo(fbo) once it's created the GLES color
*       renderbuffer + FBO bound to the CAEAGLLayer. SwapScreenBuffer() rebinds
*       this and presents.
*     - Bridge pushes touches via KitRcoreTouch{Begin,Move,End}.
*     - Bridge sets shouldClose via KitRcoreRequestClose() (e.g. on
*       applicationWillTerminate).
*
**********************************************************************************************/

#include <TargetConditionals.h>
#include <OpenGLES/ES3/gl.h>
#include <OpenGLES/ES3/glext.h>
#include <mach/mach_time.h>
#include <time.h>
#include <string.h>

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------
typedef struct {
    GLuint defaultFbo;          // FBO bound to the CAEAGLLayer color renderbuffer (owned by bridge)
    GLuint colorRbo;            // Color renderbuffer id (owned by bridge, recorded for present)
    int    pendingScreenW;      // Set by bridge before InitWindow so CORE.Window.screen agrees
    int    pendingScreenH;
    bool   closeRequested;      // Set by bridge to break WindowShouldClose loop
    void  *eaglContext;         // EAGLContext* (id), held as void* to keep this file ObjC-free
} PlatformData;

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
extern CoreData CORE;                   // Global CORE state context
static PlatformData platform = { 0 };   // Platform specific data

//----------------------------------------------------------------------------------
// Bridge entry points (declared in ios/KitBridge.h, called from KitBridge.m).
// All input/state mutations from the ObjC side land here so CORE stays this
// file's responsibility.
//----------------------------------------------------------------------------------
void KitRcoreSetScreenSize(int w, int h)
{
    platform.pendingScreenW = w;
    platform.pendingScreenH = h;
    if (CORE.Window.ready)
    {
        // Resize after init (e.g. orientation change) - keep CORE in sync; the
        // bridge re-creates the FBO at the new drawable size and re-calls
        // KitRcoreSetFbo afterwards.
        CORE.Window.screen.width  = w;
        CORE.Window.screen.height = h;
        CORE.Window.render.width  = w;
        CORE.Window.render.height = h;
        CORE.Window.currentFbo.width  = w;
        CORE.Window.currentFbo.height = h;
        CORE.Window.resizedLastFrame = true;
    }
}

void KitRcoreSetFbo(unsigned int fbo, unsigned int colorRbo)
{
    platform.defaultFbo = fbo;
    platform.colorRbo   = colorRbo;
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
}

void KitRcoreSetEaglContext(void *ctx) { platform.eaglContext = ctx; }
void *KitRcoreGetEaglContext(void)     { return platform.eaglContext; }

// raylib calls glBindFramebuffer(GL_FRAMEBUFFER, 0) to "return to the screen"
// (e.g. EndTextureMode after PostFx render-to-texture). On iOS the screen is
// not FBO 0 - it's the FBO the bridge created and bound to the CAEAGLLayer's
// color renderbuffer. install-raylib-ios.sh patches rlgl.h to call this
// on iOS instead of hardcoding 0.
unsigned int KitRcoreGetDefaultFbo(void) { return platform.defaultFbo; }

void KitRcoreRequestClose(void) { platform.closeRequested = true; }

// Strdup'd into a static so CORE.Storage.basePath can outlive the caller's
// buffer (NSString.UTF8String autoreleases). Single global - basePath is set
// once at boot and never changes.
static char s_basePath[1024] = { 0 };
void KitRcoreSetStorageBasePath(const char *path)
{
    if (!path) return;
    size_t n = strlen(path);
    if (n >= sizeof s_basePath) n = sizeof s_basePath - 1;
    memcpy(s_basePath, path, n);
    s_basePath[n] = 0;
    CORE.Storage.basePath = s_basePath;
}

// Touch dispatch. The bridge passes a stable id per UITouch and coordinates in render
// pixels; we collapse them into raylib's MAX_TOUCH_POINTS slot table. raylib already
// treats touch slot 0 as the left mouse button, and the first finger moves the mouse
// position, so the game's mouse-driven UI works with taps and one-finger drags.
//
// A tap can begin and end entirely between two display-link ticks; the game would then
// never see the press. A release that lands in the same frame as its press is held
// until the next PollInputEvents, so IsMouseButtonPressed fires for even the quickest tap.
static bool s_beganThisFrame[MAX_TOUCH_POINTS];
static bool s_pendingEnd[MAX_TOUCH_POINTS];

static void follow_primary(int slot, float x, float y)
{
    if (slot == 0) CORE.Input.Mouse.currentPosition = (Vector2){ x, y };
}

static void release_slot(int i)
{
    CORE.Input.Touch.currentTouchState[i] = 0;
    CORE.Input.Touch.pointId[i] = 0;
    s_pendingEnd[i] = false;
    // Compact pointCount down to the highest still-live slot.
    int high = 0;
    for (int j = 0; j < MAX_TOUCH_POINTS; j++)
        if (CORE.Input.Touch.currentTouchState[j]) high = j + 1;
    CORE.Input.Touch.pointCount = high;
}

void KitRcoreTouchBegin(int id, float x, float y)
{
    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        if (CORE.Input.Touch.currentTouchState[i] == 0)
        {
            CORE.Input.Touch.pointId[i] = id;
            CORE.Input.Touch.position[i] = (Vector2){ x, y };
            CORE.Input.Touch.previousPosition[i] = (Vector2){ x, y };
            CORE.Input.Touch.currentTouchState[i] = 1;
            if (i + 1 > CORE.Input.Touch.pointCount) CORE.Input.Touch.pointCount = i + 1;
            s_beganThisFrame[i] = true;
            if (i == 0) CORE.Input.Mouse.previousPosition = (Vector2){ x, y };  // no jump in GetMouseDelta
            follow_primary(i, x, y);
            return;
        }
    }
}

void KitRcoreTouchMove(int id, float x, float y)
{
    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        if (CORE.Input.Touch.currentTouchState[i] && CORE.Input.Touch.pointId[i] == id)
        {
            CORE.Input.Touch.position[i] = (Vector2){ x, y };
            follow_primary(i, x, y);
            return;
        }
    }
}

void KitRcoreTouchEnd(int id)
{
    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        if (CORE.Input.Touch.currentTouchState[i] && CORE.Input.Touch.pointId[i] == id)
        {
            if (s_beganThisFrame[i]) s_pendingEnd[i] = true;  // let the game see the press first
            else release_slot(i);
            return;
        }
    }
}

//----------------------------------------------------------------------------------
// Module Internal Functions Declaration
//----------------------------------------------------------------------------------
int InitPlatform(void);          // Initialize platform (graphics, inputs and more)

//----------------------------------------------------------------------------------
// Module Functions Definition: Window and Graphics Device
//----------------------------------------------------------------------------------

bool WindowShouldClose(void)
{
    if (CORE.Window.ready) return CORE.Window.shouldClose || platform.closeRequested;
    return true;
}

void ToggleFullscreen(void)         { TRACELOG(LOG_WARNING, "ToggleFullscreen() not available on iOS"); }
void ToggleBorderlessWindowed(void) { TRACELOG(LOG_WARNING, "ToggleBorderlessWindowed() not available on iOS"); }
void MaximizeWindow(void)           { TRACELOG(LOG_WARNING, "MaximizeWindow() not available on iOS"); }
void MinimizeWindow(void)           { TRACELOG(LOG_WARNING, "MinimizeWindow() not available on iOS"); }
void RestoreWindow(void)            { TRACELOG(LOG_WARNING, "RestoreWindow() not available on iOS"); }

void SetWindowState(unsigned int flags)   { (void)flags; TRACELOG(LOG_WARNING, "SetWindowState() not available on iOS"); }
void ClearWindowState(unsigned int flags) { (void)flags; TRACELOG(LOG_WARNING, "ClearWindowState() not available on iOS"); }

void SetWindowIcon(Image image)            { (void)image; }
void SetWindowIcons(Image *images, int n)  { (void)images; (void)n; }
void SetWindowTitle(const char *title)     { CORE.Window.title = title; }
void SetWindowPosition(int x, int y)       { (void)x; (void)y; }
void SetWindowMonitor(int m)               { (void)m; }

void SetWindowMinSize(int w, int h) { CORE.Window.screenMin.width = w; CORE.Window.screenMin.height = h; }
void SetWindowMaxSize(int w, int h) { CORE.Window.screenMax.width = w; CORE.Window.screenMax.height = h; }
void SetWindowSize(int w, int h)    { (void)w; (void)h; }
void SetWindowOpacity(float o)      { (void)o; }
void SetWindowFocused(void)         {}

void *GetWindowHandle(void)          { return platform.eaglContext; }
int   GetMonitorCount(void)          { return 1; }
int   GetCurrentMonitor(void)        { return 0; }
Vector2 GetMonitorPosition(int m)    { (void)m; return (Vector2){ 0, 0 }; }
int   GetMonitorWidth(int m)         { (void)m; return CORE.Window.screen.width; }
int   GetMonitorHeight(int m)        { (void)m; return CORE.Window.screen.height; }
int   GetMonitorPhysicalWidth(int m) { (void)m; return 0; }
int   GetMonitorPhysicalHeight(int m){ (void)m; return 0; }
int   GetMonitorRefreshRate(int m)   { (void)m; return 60; }
const char *GetMonitorName(int m)    { (void)m; return "iOS"; }

Vector2 GetWindowPosition(void)      { return (Vector2){ 0, 0 }; }
Vector2 GetWindowScaleDPI(void)
{
    // Bridge already passed pixel-sized dimensions through SetScreenSize, so the
    // logical DPI factor as far as raylib is concerned is 1.0. The bridge is
    // responsible for picking pixels vs points.
    return (Vector2){ 1.0f, 1.0f };
}

void SetClipboardText(const char *text)  { (void)text; }
const char *GetClipboardText(void)       { return ""; }
Image GetClipboardImage(void)            { Image img = { 0 }; return img; }

void ShowCursor(void)    { CORE.Input.Mouse.cursorHidden = false; }
void HideCursor(void)    { CORE.Input.Mouse.cursorHidden = true; }
void EnableCursor(void)  { CORE.Input.Mouse.cursorHidden = false; }
void DisableCursor(void) { CORE.Input.Mouse.cursorHidden = true; }

// Re-bind the CAEAGLLayer-backed renderbuffer and present. The bridge calls
// [EAGLContext presentRenderbuffer:GL_RENDERBUFFER] - the platform layer just
// makes sure the right RBO is bound before that happens. Doing the actual
// present from C would force this file to import EAGL/UIKit; instead the
// bridge wraps game_step() and presents on our behalf after EndDrawing.
//
// Net effect from the game's perspective: SwapScreenBuffer is a no-op on iOS;
// presentation is implicit at the end of each game_step tick. That matches the
// emscripten model (browser composites for us) so the existing code paths are
// happy.
void SwapScreenBuffer(void)
{
    glBindFramebuffer(GL_FRAMEBUFFER, platform.defaultFbo);
}

//----------------------------------------------------------------------------------
// Module Functions Definition: Misc
//----------------------------------------------------------------------------------

double GetTime(void)
{
    struct timespec ts = { 0 };
    clock_gettime(CLOCK_MONOTONIC, &ts);
    unsigned long long ns = (unsigned long long)ts.tv_sec*1000000000ULL + (unsigned long long)ts.tv_nsec;
    return (double)(ns - CORE.Time.base)*1e-9;
}

void OpenURL(const char *url) { (void)url; /* bridge could implement via UIApplication openURL */ }

//----------------------------------------------------------------------------------
// Module Functions Definition: Inputs
//----------------------------------------------------------------------------------

int  SetGamepadMappings(const char *mappings) { (void)mappings; return 0; }
void SetGamepadVibration(int g, float l, float r, float d) { (void)g; (void)l; (void)r; (void)d; }

void SetMousePosition(int x, int y)
{
    CORE.Input.Mouse.currentPosition  = (Vector2){ (float)x, (float)y };
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
}
void SetMouseCursor(int cursor)  { (void)cursor; }
const char *GetKeyName(int key)  { (void)key; return ""; }

void PollInputEvents(void)
{
#if SUPPORT_GESTURES_SYSTEM
    UpdateGestures();
#endif

    // Reset transient per-frame state (mirrors rcore_template / rcore_android)
    CORE.Input.Keyboard.keyPressedQueueCount = 0;
    CORE.Input.Keyboard.charPressedQueueCount = 0;
    for (int i = 0; i < MAX_KEYBOARD_KEYS; i++) CORE.Input.Keyboard.keyRepeatInFrame[i] = 0;

    CORE.Input.Gamepad.lastButtonPressed = 0;

    // Snapshot previous touch + button states so this-frame transitions
    // (IsTouchPressed / IsMouseButtonPressed) work.
    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
        CORE.Input.Touch.previousTouchState[i] = CORE.Input.Touch.currentTouchState[i];
    for (int i = 0; i < MAX_MOUSE_BUTTONS; i++)
        CORE.Input.Mouse.previousButtonState[i] = CORE.Input.Mouse.currentButtonState[i];

    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
        CORE.Input.Touch.previousPosition[i] = CORE.Input.Touch.position[i];

    // the game has now seen this frame's presses: deliver any release held back for them
    for (int i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        s_beganThisFrame[i] = false;
        if (s_pendingEnd[i]) release_slot(i);
    }

    for (int i = 0; i < 260; i++)
    {
        CORE.Input.Keyboard.previousKeyState[i] = CORE.Input.Keyboard.currentKeyState[i];
        CORE.Input.Keyboard.keyRepeatInFrame[i] = 0;
    }

    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
    CORE.Input.Mouse.previousWheelMove = CORE.Input.Mouse.currentWheelMove;
    CORE.Input.Mouse.currentWheelMove = (Vector2){ 0, 0 };

    // A finger is not a mouse: once the first finger has been up for a whole frame (the game
    // has seen the release where it happened), park the pointer off screen so nothing stays
    // hovered under the last tap.
    if (!CORE.Input.Touch.currentTouchState[0] && !CORE.Input.Touch.previousTouchState[0])
    {
        CORE.Input.Mouse.currentPosition = (Vector2){ -10000, -10000 };
        CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
    }

    // Touch events arrive asynchronously via UIView gesture callbacks ->
    // KitRcoreTouch* before this PollInputEvents runs. Nothing to drain
    // here; the bridge has already mutated CORE.Input.Touch.
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

int InitPlatform(void)
{
    // GL context is created externally by the bridge BEFORE main() runs
    // InitWindow. Our job here is to record the bridge-provided framebuffer
    // dimensions into CORE and load any GL extensions raylib needs.
    if (platform.pendingScreenW > 0 && platform.pendingScreenH > 0)
    {
        CORE.Window.screen.width  = platform.pendingScreenW;
        CORE.Window.screen.height = platform.pendingScreenH;
    }

    CORE.Window.display.width  = CORE.Window.screen.width;
    CORE.Window.display.height = CORE.Window.screen.height;
    CORE.Window.render.width   = CORE.Window.screen.width;
    CORE.Window.render.height  = CORE.Window.screen.height;
    CORE.Window.currentFbo.width  = CORE.Window.render.width;
    CORE.Window.currentFbo.height = CORE.Window.render.height;
    CORE.Window.ready = true;

    // No glLoadProcAddress equivalent on iOS GLES3 - all symbols are weak-linked
    // from the OpenGLES.framework, so rlLoadExtensions(NULL) skips symbol
    // resolution and just records GL_VERSION etc.
    rlLoadExtensions(NULL);

    InitTimer();

    // The bridge sets the storage base path (Documents) before InitWindow; keep it, or
    // TakeScreenshot and friends write to "/" and fail.
    CORE.Storage.basePath = s_basePath;

    TRACELOG(LOG_INFO, "PLATFORM: IOS: Initialized successfully (%dx%d)",
             CORE.Window.screen.width, CORE.Window.screen.height);
    return 0;
}

void ClosePlatform(void)
{
    // GL context teardown is the bridge's responsibility - it owns the
    // EAGLContext + CAEAGLLayer lifecycle.
    platform.defaultFbo = 0;
    platform.colorRbo = 0;
}

// EOF
