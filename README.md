//
//  ZoneKit.md
//  ZoneKit Readme
//
//  Created by Dustin Nielson on 2/27/26.
//


# ZoneKit

## Description
ZoneKit enables a simple unified way to deliver Metal textures to clients.

- Video to MTLTexture
- USB Device and iOS Capture to MTLTexture
- Screen Capture to MTLTexture (via ScreenCaptureKit)
- VirtualDisplay to MTLTexture (zero-copy IOSurface)

## Abstraction List
ZoneKit provides a simple list of available sources (`[ZoneKitSource]`) in an array for simple discovery.

## Products

| Product | Purpose |
|---------|---------|
| `ZoneKit` | Capture management, virtual display, source discovery |
| `ZoneLayoutGenerator` | Zone layout calculation from constraint strings |
| `TextureCompositorEngine` | Multi-zone Metal texture compositing engine |
| `VideoPlayerKit` | Video playback with pull-based frame extraction |

## Virtual Display (macOS only)

ZoneKit manages headless virtual displays via CGVirtualDisplay (private API) with CGDisplayStream capture and zero-copy IOSurface-to-MTLTexture conversion.

### Architecture

```
ZoneKit.addVirtualDisplay(identifier:configuration:)
  -> CGVirtualDisplay (private API) creates headless screen
    -> NSScreen.screens polling (up to 5s) confirms display ready
      -> CGDisplayStream capture (via C wrapper for macOS 15+ Swift availability)
        -> IOSurface frames
          -> MTLTexture (zero-copy: device.makeTexture(iosurface:))
          -> Preview window (layer.contents = surface)
```

### Lifecycle

```swift
// Create — starts capture automatically
let source = zoneKit.addVirtualDisplay(
    identifier: "expo",
    configuration: .preset4K
)

// Ready callback — displayID available for CaptureKit matching
func zoneKitVirtualDisplayDidBecomeReady(source: ZoneKitSource, displayID: CGDirectDisplayID) {
    virtualDisplayID = displayID  // CaptureKit matches "screenx{displayID}"
}

// Preview window — interactive preview for widescreen hardware configs
let window = zoneKit.createPreviewWindow(
    for: "expo",
    title: "Virtual Display Preview",
    initialSize: CGSize(width: 960, height: 540),
    minSize: CGSize(width: 480, height: 270)
)

// Texture output — available for future direct injection bypassing CaptureKit
func zoneKitVirtualDisplayDidOutputTexture(texture: MTLTexture, source: ZoneKitSource) {
    // Future: inject directly into zone pipeline
}

// Teardown
zoneKit.removeVirtualDisplay(identifier: "expo")
```

### Preview Window

`createPreviewWindow(for:title:initialSize:minSize:)` creates an NSWindow containing a `ZoneKitVirtualDisplayPreviewView` that renders IOSurface frames from the virtual display's existing CGDisplayStream (no duplicate capture stream). The view supports click-to-cursor coordinate conversion via `onTap`/`onDoubleTap` callbacks for interactive use.

Note: Click-to-cursor relay is not wired by default. `CGDisplayMoveCursorToPoint` moves the system cursor to the virtual display coordinate space, which causes macOS to activate Finder (the Desktop owner on the headless surface). Consumers should wire `onTap` externally with focus management (e.g., `NSApp.activate` after cursor move) if cursor relay is needed.

### Configurations

| Preset | Max Resolution | Display Modes | HiDPI |
|--------|---------------|---------------|-------|
| `.preset4K` | 3840x2160 | 4K, 1440p, 1080p | Yes |
| `.preset1080p` | 1920x1080 | 1080p | No |

### CGDisplayStream Compatibility

CGDisplayStream APIs are marked unavailable from Swift on macOS 14+, but the underlying C functions still work and are specifically required for capturing virtual displays (ScreenCaptureKit has known issues with them). ZoneKit uses a C wrapper (`CZoneKitVirtualDisplayPrivate`) to call these functions, bypassing Swift availability checks.

