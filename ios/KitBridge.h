// KitBridge.h - the C interface between the Objective-C shell (KitBridge.m) and raylib's
// iOS platform layer (rcore_ios.c). The game itself never includes this: it only sees kit.h.
#ifndef KIT_BRIDGE_H
#define KIT_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

void KitRcoreSetScreenSize(int w, int h);
void KitRcoreSetFbo(unsigned int fbo, unsigned int colorRbo);
void KitRcoreSetEaglContext(void *eaglCtx);
void *KitRcoreGetEaglContext(void);
void KitRcoreRequestClose(void);
void KitRcoreSetStorageBasePath(const char *path);

void KitRcoreTouchBegin(int id, float x, float y);
void KitRcoreTouchMove(int id, float x, float y);
void KitRcoreTouchEnd(int id);

#ifdef __cplusplus
}
#endif

#endif // KIT_BRIDGE_H
