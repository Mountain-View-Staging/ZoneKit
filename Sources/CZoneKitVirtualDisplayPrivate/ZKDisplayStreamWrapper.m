//
//  ZKDisplayStreamWrapper.m
//  ZoneKit
//
//  Objective-C implementation of CGDisplayStream wrapper.
//  These APIs are marked unavailable from Swift on macOS 15+ but the underlying
//  CoreGraphics C functions still work and are specifically needed for capturing
//  virtual displays (ScreenCaptureKit has known issues with virtual displays).
//
//  Uses dlsym() at runtime to resolve CGDisplayStream symbols, bypassing
//  both Swift availability checks and Clang unavailability errors.
//

#import "ZKDisplayStreamWrapper.h"
#import <dlfcn.h>

// Block type for the CGDisplayStream handler
typedef void (^DisplayStreamHandler)(
    int32_t status,
    uint64_t displayTime,
    IOSurfaceRef _Nullable frameSurface,
    void * _Nullable updateRef
);

// Function pointer types matching the CGDisplayStream C API signatures.
// We use void* for the stream type to avoid referencing CGDisplayStreamRef
// which is marked unavailable at compile time.
typedef void* (*CreateWithQueueFunc)(
    CGDirectDisplayID display,
    size_t outputWidth,
    size_t outputHeight,
    int32_t pixelFormat,
    CFDictionaryRef _Nullable properties,
    dispatch_queue_t _Nonnull queue,
    DisplayStreamHandler _Nonnull handler
);

typedef CGError (*StreamStartFunc)(void * _Nonnull stream);
typedef CGError (*StreamStopFunc)(void * _Nonnull stream);

// Lazily resolved function pointers
static CreateWithQueueFunc _streamCreate = NULL;
static StreamStartFunc _streamStart = NULL;
static StreamStopFunc _streamStop = NULL;
static CFStringRef _showCursorKey = NULL;
static CFStringRef _minFrameTimeKey = NULL;
static bool _resolved = false;

static void resolveSymbols(void) {
    if (_resolved) return;
    _resolved = true;

    void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    if (!cg) return;

    _streamCreate = (CreateWithQueueFunc)dlsym(cg, "CGDisplayStreamCreateWithDispatchQueue");
    _streamStart = (StreamStartFunc)dlsym(cg, "CGDisplayStreamStart");
    _streamStop = (StreamStopFunc)dlsym(cg, "CGDisplayStreamStop");

    // Resolve property key symbols
    CFStringRef *showCursorPtr = (CFStringRef *)dlsym(cg, "kCGDisplayStreamShowCursor");
    CFStringRef *minFrameTimePtr = (CFStringRef *)dlsym(cg, "kCGDisplayStreamMinimumFrameTime");

    if (showCursorPtr) _showCursorKey = *showCursorPtr;
    if (minFrameTimePtr) _minFrameTimeKey = *minFrameTimePtr;

    // Note: we intentionally don't dlclose(cg) — CoreGraphics is already loaded
    // and we need the symbols to remain valid.
}

ZKDisplayStreamRef _Nullable ZKDisplayStreamCreate(
    CGDirectDisplayID displayID,
    size_t outputWidth,
    size_t outputHeight,
    int32_t pixelFormat,
    bool showCursor,
    double minimumFrameTime,
    dispatch_queue_t _Nonnull queue,
    ZKDisplayStreamFrameCallback _Nonnull callback,
    void * _Nullable context
) {
    resolveSymbols();

    if (!_streamCreate) return NULL;

    // Build the properties dictionary
    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    if (!properties) return NULL;

    // showCursor
    if (_showCursorKey) {
        CFDictionarySetValue(properties, _showCursorKey,
                             showCursor ? kCFBooleanTrue : kCFBooleanFalse);
    }

    // minimumFrameTime
    if (_minFrameTimeKey) {
        CFNumberRef frameTime = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &minimumFrameTime);
        if (frameTime) {
            CFDictionarySetValue(properties, _minFrameTimeKey, frameTime);
            CFRelease(frameTime);
        }
    }

    void *stream = _streamCreate(
        displayID,
        outputWidth,
        outputHeight,
        pixelFormat,
        properties,
        queue,
        ^(int32_t status, uint64_t displayTime,
          IOSurfaceRef _Nullable frameSurface, void * _Nullable updateRef) {
            callback(status, displayTime, frameSurface, updateRef, context);
        }
    );

    CFRelease(properties);
    return (ZKDisplayStreamRef)stream;
}

CGError ZKDisplayStreamStart(ZKDisplayStreamRef _Nonnull stream) {
    resolveSymbols();
    if (!_streamStart) return kCGErrorFailure;
    return _streamStart((void *)stream);
}

CGError ZKDisplayStreamStop(ZKDisplayStreamRef _Nonnull stream) {
    resolveSymbols();
    if (!_streamStop) return kCGErrorFailure;
    return _streamStop((void *)stream);
}

void ZKDisplayStreamRelease(ZKDisplayStreamRef _Nonnull stream) {
    CFRelease((CFTypeRef)stream);
}
