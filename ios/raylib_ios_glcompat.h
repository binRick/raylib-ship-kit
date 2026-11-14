// Compatibility shim included via -include when compiling raylib for iOS.
//
// raylib's rlgl.h references several GLES extension constants by their
// _OES / _EXT suffixed names (the GLES2-era extension spellings). Apple's
// OpenGLES.framework only ships the un-suffixed core GLES3 names (and only
// some of the extension equivalents). Map each one back to a core type
// that's a reasonable substitute on iOS.

#ifndef KIT_IOS_GLCOMPAT_H
#define KIT_IOS_GLCOMPAT_H

#include <OpenGLES/ES3/gl.h>
#include <OpenGLES/ES3/glext.h>

#ifndef GL_DEPTH_COMPONENT32_OES
#define GL_DEPTH_COMPONENT32_OES GL_DEPTH_COMPONENT24
#endif
#ifndef GL_DEPTH_COMPONENT24_OES
#define GL_DEPTH_COMPONENT24_OES GL_DEPTH_COMPONENT24
#endif

#ifndef GL_R32F_EXT
#define GL_R32F_EXT     GL_R32F
#endif
#ifndef GL_RGB32F_EXT
#define GL_RGB32F_EXT   GL_RGB32F
#endif
#ifndef GL_RGBA32F_EXT
#define GL_RGBA32F_EXT  GL_RGBA32F
#endif
#ifndef GL_R16F_EXT
#define GL_R16F_EXT     GL_R16F
#endif
#ifndef GL_RGB16F_EXT
#define GL_RGB16F_EXT   GL_RGB16F
#endif
#ifndef GL_RGBA16F_EXT
#define GL_RGBA16F_EXT  GL_RGBA16F
#endif
#ifndef GL_RED_EXT
#define GL_RED_EXT      GL_RED
#endif
#ifndef GL_RG_EXT
#define GL_RG_EXT       GL_RG
#endif

#ifndef GL_LUMINANCE
#define GL_LUMINANCE       GL_RED
#endif
#ifndef GL_LUMINANCE_ALPHA
#define GL_LUMINANCE_ALPHA GL_RG
#endif

// MRT color attachment names. Core GLES3 has GL_COLOR_ATTACHMENT0..15
// without the _EXT suffix; raylib's MRT path spells them with _EXT.
#ifndef GL_COLOR_ATTACHMENT0_EXT
#define GL_COLOR_ATTACHMENT0_EXT GL_COLOR_ATTACHMENT0
#endif
#ifndef GL_COLOR_ATTACHMENT1_EXT
#define GL_COLOR_ATTACHMENT1_EXT GL_COLOR_ATTACHMENT1
#endif
#ifndef GL_COLOR_ATTACHMENT2_EXT
#define GL_COLOR_ATTACHMENT2_EXT GL_COLOR_ATTACHMENT2
#endif
#ifndef GL_COLOR_ATTACHMENT3_EXT
#define GL_COLOR_ATTACHMENT3_EXT GL_COLOR_ATTACHMENT3
#endif
#ifndef GL_COLOR_ATTACHMENT4_EXT
#define GL_COLOR_ATTACHMENT4_EXT GL_COLOR_ATTACHMENT4
#endif
#ifndef GL_COLOR_ATTACHMENT5_EXT
#define GL_COLOR_ATTACHMENT5_EXT GL_COLOR_ATTACHMENT5
#endif
#ifndef GL_COLOR_ATTACHMENT6_EXT
#define GL_COLOR_ATTACHMENT6_EXT GL_COLOR_ATTACHMENT6
#endif
#ifndef GL_COLOR_ATTACHMENT7_EXT
#define GL_COLOR_ATTACHMENT7_EXT GL_COLOR_ATTACHMENT7
#endif

#endif
