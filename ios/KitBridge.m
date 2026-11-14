// KitBridge.m - UIKit + CAEAGLLayer + CADisplayLink shell that hosts the
// game's per-frame game_step() under iOS.
//
// Lifecycle:
//   1. main() -> UIApplicationMain -> KitAppDelegate
//   2. SceneDelegate creates UIWindow with KitGameViewController as root
//   3. GameVC.viewDidLoad creates EAGLContext (GLES3) + CAEAGLLayer-backed
//      view, wires color+depth renderbuffers + a default FBO, then calls
//      game_init().
//   4. CADisplayLink fires render: -> bind FBO -> game_step() -> present.
//   5. AppDelegate.applicationWillTerminate -> KitRcoreRequestClose()
//      then game_shutdown().
//
// Touch dispatch routes through KitRcoreTouch{Begin,Move,End}: the first finger
// drives raylib's mouse (so mouse-driven code just works), and every finger is
// also a raylib touch point for multi-touch.

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <objc/runtime.h>

#import "KitBridge.h"
#import "kit.h"

static int s_argc;
static char **s_argv;

// ── EAGL view: a UIView whose backing layer is a CAEAGLLayer ────────────────

@interface KitEAGLView : UIView
@end

@implementation KitEAGLView
+ (Class)layerClass { return [CAEAGLLayer class]; }
@end

// ── Game view controller ────────────────────────────────────────────────────

@interface KitGameViewController : UIViewController
{
    EAGLContext   *_glContext;
    CADisplayLink *_displayLink;
    GLuint         _colorRbo;
    GLuint         _depthRbo;
    GLuint         _defaultFbo;
    int            _backingW;
    int            _backingH;
    BOOL           _gameInitialized;
}
@end

@implementation KitGameViewController

- (void)loadView
{
    // Manual UIView so we can use KitEAGLView (CAEAGLLayer-backed). The
    // default loadView gives a plain UIView, which can't host GLES rendering.
    self.view = [[KitEAGLView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
    // Render at the screen's real pixel density. A game whose UI is laid out in fixed desktop
    // pixels can set this to 1.0 instead: it then draws in points (an iPad is 1024-1376 wide).
    self.view.contentScaleFactor = [UIScreen mainScreen].nativeScale;
    self.view.multipleTouchEnabled = YES;

    CAEAGLLayer *layer = (CAEAGLLayer *)self.view.layer;
    layer.opaque = YES;
    layer.contentsScale = self.view.contentScaleFactor;
    layer.drawableProperties = @{
        kEAGLDrawablePropertyRetainedBacking: @NO,
        kEAGLDrawablePropertyColorFormat:     kEAGLColorFormatRGBA8
    };
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!_glContext)
    {
        NSLog(@"kit: failed to create GLES3 context");
        return;
    }
    [EAGLContext setCurrentContext:_glContext];
    KitRcoreSetEaglContext((__bridge void *)_glContext);

    [self createFramebuffer];

    // Saves go in Documents: the app bundle the game runs from is read-only.
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    KitRcoreSetStorageBasePath(docs.UTF8String);
    kit_set_save_dir(docs.UTF8String);

    // Hand the real drawable size to rcore: on iOS it replaces whatever size the
    // game passes to InitWindow().
    KitRcoreSetScreenSize(_backingW, _backingH);

    game_init(s_argc, s_argv);
    _gameInitialized = YES;

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
    _displayLink.preferredFramesPerSecond = 60;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // iOS kills an app that issues GL calls in the background: stop the frames while away
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                usingBlock:^(NSNotification *n) { self->_displayLink.paused = YES; }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil
                usingBlock:^(NSNotification *n) { self->_displayLink.paused = NO; }];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // Re-create the renderbuffers if the drawable size changed (rotation,
    // safe-area changes). Bail if nothing to update.
    CAEAGLLayer *layer = (CAEAGLLayer *)self.view.layer;
    CGSize sz = layer.bounds.size;
    int newW = (int)(sz.width  * layer.contentsScale);
    int newH = (int)(sz.height * layer.contentsScale);
    if ((newW == _backingW && newH == _backingH) || newW == 0 || newH == 0) return;
    [EAGLContext setCurrentContext:_glContext];
    [self destroyFramebuffer];
    [self createFramebuffer];
    if (_gameInitialized) KitRcoreSetScreenSize(_backingW, _backingH);
}

- (void)createFramebuffer
{
    CAEAGLLayer *layer = (CAEAGLLayer *)self.view.layer;

    glGenRenderbuffers(1, &_colorRbo);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRbo);
    [_glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH,  &_backingW);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingH);

    glGenRenderbuffers(1, &_depthRbo);
    glBindRenderbuffer(GL_RENDERBUFFER, _depthRbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, _backingW, _backingH);

    glGenFramebuffers(1, &_defaultFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFbo);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,        GL_RENDERBUFFER, _colorRbo);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _depthRbo);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE)
        NSLog(@"kit: framebuffer incomplete: 0x%04x", status);

    KitRcoreSetFbo(_defaultFbo, _colorRbo);
}

- (void)destroyFramebuffer
{
    if (_defaultFbo) { glDeleteFramebuffers(1, &_defaultFbo); _defaultFbo = 0; }
    if (_colorRbo)   { glDeleteRenderbuffers(1, &_colorRbo);  _colorRbo   = 0; }
    if (_depthRbo)   { glDeleteRenderbuffers(1, &_depthRbo);  _depthRbo   = 0; }
}

- (void)renderFrame:(CADisplayLink *)link
{
    if (!_gameInitialized) return;
    [EAGLContext setCurrentContext:_glContext];
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFbo);

    game_step();

    // Present the color renderbuffer that's bound to the CAEAGLLayer. The
    // game's EndDrawing already called rlDrawRenderBatchActive + glFlush
    // implicitly via raylib, so the GPU side is settled.
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRbo);
    [_glContext presentRenderbuffer:GL_RENDERBUFFER];
}

// ── Touch dispatch ───────────────────────────────────────────────────────────
// Each UITouch gets a fresh monotonically-increasing id stamped on it at
// Begin. Hashing the UITouch* pointer is not safe: UIKit recycles touch objects
// at the same address, so lifting one finger and tapping with another inside a
// frame looks like the same touch and the second tap is lost.
static char kTouchIdKey;
static int  s_nextTouchId = 1;

static int TouchID(UITouch *t, bool isBegin)
{
    NSNumber *n = objc_getAssociatedObject(t, &kTouchIdKey);
    if (isBegin || !n) {
        if (s_nextTouchId >= 0x7FFFFFFF) s_nextTouchId = 1;
        n = @(s_nextTouchId++);
        objc_setAssociatedObject(t, &kTouchIdKey, n, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return n.intValue;
}

- (void)dispatchTouches:(NSSet<UITouch *> *)touches mode:(int)mode
{
    CGFloat scale = self.view.contentScaleFactor;
    for (UITouch *t in touches)
    {
        CGPoint p = [t locationInView:self.view];
        float x = (float)(p.x * scale);
        float y = (float)(p.y * scale);
        int id = TouchID(t, mode == 0);
        if      (mode == 0) KitRcoreTouchBegin(id, x, y);
        else if (mode == 1) KitRcoreTouchMove (id, x, y);
        else                KitRcoreTouchEnd  (id);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event     { [self dispatchTouches:touches mode:0]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event     { [self dispatchTouches:touches mode:1]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event     { [self dispatchTouches:touches mode:2]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self dispatchTouches:touches mode:2]; }

// Landscape only. For portrait, change this and UISupportedInterfaceOrientations in Info.plist.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
// Drags that start near a screen edge would otherwise be taken by Control Centre and the
// home indicator. Deferring makes iOS require a second swipe for system UI.
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }

@end

// ── Scene delegate ───────────────────────────────────────────────────────────
// iOS 27 traps (EXC_BREAKPOINT in _UIApplicationEvaluateRuntimeIssueFor
// NoSceneLifecycleAdoption) at launch for apps linked against the iOS 27 SDK
// that still create their window in the app delegate. The window lives here
// now; Info.plist's UIApplicationSceneManifest names this class.

@interface KitSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation KitSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[KitGameViewController alloc] init];
    [self.window makeKeyAndVisible];
}

@end

// ── App delegate ─────────────────────────────────────────────────────────────

@interface KitAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation KitAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    KitRcoreRequestClose();
    game_shutdown();
}

@end

// ── Entry point ──────────────────────────────────────────────────────────────

int main(int argc, char *argv[])
{
    // launch arguments reach the game, e.g. `xcrun simctl launch booted <bundle id> --debug`
    s_argc = argc;
    s_argv = argv;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([KitAppDelegate class]));
    }
}
