//
//  ZoneKitVirtualDisplayPreviewView.swift
//  ZoneKit
//
//  NSView that renders virtual display content to a CALayer for interactive preview.
//  Receives IOSurface frames from ZoneKitVirtualDisplay's onFrameAvailable callback
//  and renders them via layer.contents (no duplicate CGDisplayStream needed).
//
//  Supports click-to-cursor coordinate conversion for interactive use in
//  hardware configurations where the virtual display serves as a control surface.
//

#if os(macOS)

import AppKit
import IOSurface
import CoreGraphics
import OSLog
import LoggingKit

// MARK: - ZoneKitVirtualDisplayPreviewView

/// Renders virtual display content for interactive preview.
///
/// Attach to a `ZoneKitVirtualDisplay` to receive IOSurface frames rendered
/// to the view's backing layer. Click coordinates are converted to display
/// coordinates and forwarded via the `onTap` callback.
public class ZoneKitVirtualDisplayPreviewView: NSView {

    // MARK: - Public Properties

    /// Called when the view is clicked, with the point in display coordinates (origin top-left).
    public var onTap: ((CGPoint) -> Void)?

    /// Called when the view is double-clicked, with the point in display coordinates.
    public var onDoubleTap: ((CGPoint) -> Void)?

    // MARK: - Private Properties

    /// The display resolution used for coordinate conversion.
    private var displayResolution: CGSize = .zero

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Click gesture for cursor relay
        let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClick(_:)))
        singleClick.numberOfClicksRequired = 1
        addGestureRecognizer(singleClick)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)

        singleClick.shouldRequireFailure(of: doubleClick)
    }

    // MARK: - Attachment

    /// Attach to a virtual display to start receiving frames.
    ///
    /// Sets the `onFrameAvailable` callback on the virtual display instance.
    /// Only one preview view should be attached at a time.
    ///
    /// - Parameters:
    ///   - virtualDisplay: The virtual display to preview.
    ///   - resolution: The display resolution for coordinate conversion.
    func attach(_ virtualDisplay: ZoneKitVirtualDisplay, resolution: CGSize) {
        displayResolution = resolution

        virtualDisplay.onFrameAvailable = { [weak self] surface in
            self?.layer?.contents = surface
        }

        mlog.debug("[PreviewView] Attached to virtual display, resolution: \(resolution)")
    }

    /// Detach from the current virtual display.
    func detach(from virtualDisplay: ZoneKitVirtualDisplay) {
        virtualDisplay.onFrameAvailable = nil
        layer?.contents = nil
        displayResolution = .zero
    }

    // MARK: - Coordinate Conversion

    /// Converts a point in view coordinates to display coordinates.
    /// - Parameter viewPoint: Point in view coordinates (origin bottom-left).
    /// - Returns: Point in display coordinates (origin top-left), or nil if not configured.
    public func convertToDisplayCoordinates(_ viewPoint: NSPoint) -> NSPoint? {
        guard displayResolution != .zero else { return nil }

        let normalizedX = viewPoint.x / bounds.width
        // Flip Y coordinate (view origin is bottom-left, display origin is top-left)
        let normalizedY = (bounds.height - viewPoint.y) / bounds.height

        return NSPoint(
            x: normalizedX * displayResolution.width,
            y: normalizedY * displayResolution.height
        )
    }

    // MARK: - Click Handling

    @objc private func handleSingleClick(_ gesture: NSClickGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        if let displayPoint = convertToDisplayCoordinates(viewPoint) {
            onTap?(displayPoint)
        }
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        if let displayPoint = convertToDisplayCoordinates(viewPoint) {
            onDoubleTap?(displayPoint)
        }
    }
}

#endif
