//
//  ZKDisplayStreamWrapper.h
//  ZoneKit
//
//  C wrapper for CGDisplayStream APIs that are marked unavailable in Swift
//  on macOS 14+. The underlying C APIs still work and are required for
//  capturing virtual displays (ScreenCaptureKit does not reliably capture them).
//
//  Uses dlsym() at runtime to resolve CGDisplayStream symbols, bypassing
//  both Swift availability checks and Clang unavailability errors.
//
//  Note: We use our own opaque type (ZKDisplayStreamRef) rather than
//  CGDisplayStreamRef to avoid Swift's unavailability annotations on the type.
//

#ifndef ZKDisplayStreamWrapper_h
#define ZKDisplayStreamWrapper_h

#include <CoreGraphics/CoreGraphics.h>
#include <IOSurface/IOSurface.h>

/// Opaque wrapper type for CGDisplayStream, used to bypass Swift availability annotations.
typedef struct ZKDisplayStreamOpaque *ZKDisplayStreamRef;

/// Frame status values matching CGDisplayStreamFrameStatus
enum {
    ZKFrameStatusComplete = 0,   // kCGDisplayStreamFrameStatusFrameComplete
    ZKFrameStatusIdle = 1,       // kCGDisplayStreamFrameStatusFrameIdle
    ZKFrameStatusBlank = 2,      // kCGDisplayStreamFrameStatusFrameBlank
    ZKFrameStatusStopped = 3,    // kCGDisplayStreamFrameStatusStopped
};
typedef int32_t ZKFrameStatus;

/// Callback type for display stream frame delivery.
/// Parameters: status, displayTime, ioSurface, updateRef, context
typedef void (*ZKDisplayStreamFrameCallback)(
    ZKFrameStatus status,
    uint64_t displayTime,
    IOSurfaceRef _Nullable frameSurface,
    void * _Nullable updateRef,
    void * _Nullable context
);

/// Creates and returns a display stream for the given display.
/// Returns NULL on failure. The caller must call ZKDisplayStreamStop and ZKDisplayStreamRelease when done.
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
);

/// Starts the display stream. Returns kCGErrorSuccess on success.
CGError ZKDisplayStreamStart(ZKDisplayStreamRef _Nonnull stream);

/// Stops the display stream. Returns kCGErrorSuccess on success.
CGError ZKDisplayStreamStop(ZKDisplayStreamRef _Nonnull stream);

/// Releases the display stream (calls CFRelease).
void ZKDisplayStreamRelease(ZKDisplayStreamRef _Nonnull stream);

#endif /* ZKDisplayStreamWrapper_h */
