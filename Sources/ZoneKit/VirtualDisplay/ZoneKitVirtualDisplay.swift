//
//  ZoneKitVirtualDisplay.swift
//  ZoneKit
//
//  Created by Dustin Nielson on 2/27/26.
//
//  Manages a headless virtual display that delivers MTLTexture frames.
//
//  Architecture:
//    CGVirtualDisplay (private API) → CGDisplayStream capture → IOSurface → MTLTexture (zero-copy)
//
//  The virtual display runs in the background and mirrors to a real display.
//  Frame capture uses CGDisplayStream (preferred over ScreenCaptureKit for virtual displays).
//  IOSurface frames are converted to MTLTexture via device.makeTexture(iosurface:) — no memcpy.
//

#if os(macOS)

import Foundation
import AppKit
import Metal
import CoreGraphics
import IOSurface
import CZoneKitVirtualDisplayPrivate
import OSLog
import LoggingKit

// MARK: - ZoneKitVirtualDisplayDelegate

/// Internal delegate protocol for virtual display events.
/// ZoneKit.swift conforms to this to forward textures to the public ZoneKitDelegate.
protocol ZoneKitVirtualDisplayDelegate: AnyObject {
    func zoneKitVirtualDisplayDidOutputTexture(texture: MTLTexture, source: ZoneKitSource)
    func zoneKitVirtualDisplayDidBecomeReady(source: ZoneKitSource, displayID: CGDirectDisplayID)
}

// MARK: - ZoneKitVirtualDisplay

/// Wraps CGVirtualDisplay + CGDisplayStream to provide MTLTexture frame delivery.
///
/// Usage:
/// 1. Create via `ZoneKit.addVirtualDisplay(identifier:configuration:)`
/// 2. Call `startCapture()` to create the display and begin streaming
/// 3. Receive `MTLTexture` via delegate callback
/// 4. Call `stopCapture()` to tear down
public class ZoneKitVirtualDisplay: NSObject {

    // MARK: - Public Properties

    /// The capture source descriptor for this virtual display.
    /// Used by ZoneKit to identify this source in enable/disable/emit calls.
    public private(set) var captureSource: ZoneKitSource?

    /// The CoreGraphics display ID, available after the display is created.
    /// Consumers may need this for display arrangement (e.g., CGConfigureDisplayOrigin).
    public private(set) var displayID: CGDirectDisplayID?

    /// Whether capture is currently active and delivering frames.
    public private(set) var isCapturing: Bool = false

    /// Optional callback for raw IOSurface frames — used by the preview view
    /// to render display content to a CALayer without creating a second capture stream.
    var onFrameAvailable: ((IOSurface) -> Void)?

    // MARK: - Internal Properties

    weak var delegate: ZoneKitVirtualDisplayDelegate?

    // MARK: - Private Properties

    /// User-provided identifier for this instance
    private let identifier: String

    /// Configuration used to create the virtual display
    let configuration: ZoneKitVirtualDisplayConfiguration

    /// The private-API virtual display object
    private var virtualDisplay: CGVirtualDisplay?

    /// CGDisplayStream for capturing the virtual display contents (via C wrapper).
    /// Uses ZKDisplayStreamRef (our opaque wrapper type) because CGDisplayStream
    /// is marked unavailable in Swift on macOS 15+.
    private var displayStream: ZKDisplayStreamRef?

    /// Metal device for zero-copy texture creation
    private let metalDevice: MTLDevice?

    /// Timer for polling NSScreen.screens to find the virtual display
    private var retryTimer: Timer?
    private var retryCount: Int = 0
    private static let maxRetries = 50       // 50 × 0.1s = 5 seconds
    private static let retryInterval: TimeInterval = 0.1

    /// Retained context pointer for the C display stream callback.
    /// Must be released when the stream is stopped.
    private var streamContext: UnsafeMutableRawPointer?

    /// Screen change observer token
    private var screenChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Creates a new virtual display source.
    /// - Parameters:
    ///   - identifier: Unique string identifier for this source
    ///   - delegate: Delegate to receive texture frames and lifecycle events
    ///   - configuration: Display configuration (defaults to 1080p)
    init(
        identifier: String,
        delegate: ZoneKitVirtualDisplayDelegate,
        configuration: ZoneKitVirtualDisplayConfiguration = .preset1080p
    ) {
        self.identifier = identifier
        self.delegate = delegate
        self.configuration = configuration
        self.metalDevice = MTLCreateSystemDefaultDevice()

        super.init()

        // Build the ZoneKitSource descriptor
        self.captureSource = ZoneKitSource(
            id: "virtual-display-\(identifier)",
            type: .virtualDisplay,
            displayName: configuration.name,
            manufacturer: "Virtual",
            modelID: "ZoneKitVirtualDisplay",
            uniqueID: "virtual-display-\(identifier)"
        )

        mlog.debug("[ZoneKitVirtualDisplay] Initialized: \(identifier) (\(configuration.maxWidth)x\(configuration.maxHeight))")
    }

    deinit {
        tearDown()
        mlog.debug("[ZoneKitVirtualDisplay] Deinitialized: \(identifier)")
    }

    // MARK: - Capture Control

    /// Creates the virtual display and starts CGDisplayStream capture.
    /// Frame delivery begins after the display is found in NSScreen.screens (up to ~5 seconds).
    func startCapture() {
        guard !isCapturing else {
            mlog.debug("[ZoneKitVirtualDisplay] Already capturing: \(identifier)")
            return
        }
        guard metalDevice != nil else {
            mlog.error("[ZoneKitVirtualDisplay] No Metal device available — cannot start")
            return
        }

        mlog.info("[ZoneKitVirtualDisplay] Starting: \(identifier)")

        // Create the virtual display via private API
        createVirtualDisplay()

        isCapturing = true
    }

    /// Stops capture and tears down the virtual display.
    func stopCapture() {
        stopCapture(completion: nil)
    }

    /// Stops capture with a completion callback (fires on main thread).
    func stopCapture(completion: (() -> Void)?) {
        guard isCapturing else {
            mlog.debug("[ZoneKitVirtualDisplay] Not capturing: \(identifier)")
            completion?()
            return
        }

        mlog.info("[ZoneKitVirtualDisplay] Stopping: \(identifier)")
        tearDown()
        isCapturing = false

        if let completion {
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Virtual Display Creation

    private func createVirtualDisplay() {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = configuration.name
        descriptor.maxPixelsWide = configuration.maxWidth
        descriptor.maxPixelsHigh = configuration.maxHeight
        descriptor.sizeInMillimeters = configuration.physicalSizeMillimeters
        descriptor.vendorID = configuration.vendorID
        descriptor.productID = configuration.productID
        descriptor.serialNum = configuration.serialNumber
        descriptor.setDispatchQueue(DispatchQueue.main)

        descriptor.terminationHandler = { [weak self] _, _ in
            guard let self = self else { return }
            mlog.warning("[ZoneKitVirtualDisplay] Display terminated externally: \(self.identifier)")
            self.tearDown()
            self.isCapturing = false
        }

        let display = CGVirtualDisplay(descriptor: descriptor)

        // Apply display modes and HiDPI settings
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = configuration.hiDPIEnabled ? 1 : 0
        settings.modes = configuration.displayModes.map { mode in
            CGVirtualDisplayMode(
                width: UInt(mode.width),
                height: UInt(mode.height),
                refreshRate: mode.refreshRate
            )
        }

        guard display.apply(settings) else {
            mlog.error("[ZoneKitVirtualDisplay] Failed to apply display settings")
            return
        }

        self.virtualDisplay = display
        self.displayID = display.displayID

        mlog.info("[ZoneKitVirtualDisplay] Created display ID: \(display.displayID)")

        // Start polling for the display to appear in NSScreen.screens
        startRetryLoop()
    }

    // MARK: - Display Retry Loop

    /// Polls NSScreen.screens until the virtual display appears.
    /// Once found, starts the CGDisplayStream capture.
    private func startRetryLoop() {
        retryCount = 0

        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.retryCount += 1

            if let _ = self.findScreen() {
                timer.invalidate()
                self.retryTimer = nil
                self.onDisplayReady()
            } else if self.retryCount >= Self.maxRetries {
                timer.invalidate()
                self.retryTimer = nil
                mlog.error("[ZoneKitVirtualDisplay] Display not found after \(Self.maxRetries) retries")
            }
        }
    }

    /// Finds the NSScreen matching our virtual display ID.
    private func findScreen() -> NSScreen? {
        guard let displayID = self.displayID else { return nil }
        return NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return screenID == displayID
        }
    }

    /// Called when the virtual display is found in NSScreen.screens.
    private func onDisplayReady() {
        guard let displayID = self.displayID, let source = self.captureSource else { return }

        mlog.info("[ZoneKitVirtualDisplay] Display ready: \(identifier) (ID: \(displayID))")

        // Notify delegate
        delegate?.zoneKitVirtualDisplayDidBecomeReady(source: source, displayID: displayID)

        // Start the display stream
        startDisplayStream(displayID: displayID)

        // Observe screen changes for reconfiguration
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let displayID = self.displayID else { return }
            mlog.debug("[ZoneKitVirtualDisplay] Screen parameters changed, reconfiguring stream")
            self.stopDisplayStream()
            self.startDisplayStream(displayID: displayID)
        }
    }

    // MARK: - CGDisplayStream (via C wrapper)
    //
    // CGDisplayStream APIs are marked unavailable from Swift on macOS 14+,
    // but the underlying C functions still work and are specifically required
    // for capturing virtual displays (ScreenCaptureKit has known issues with them).
    // We call through ZKDisplayStreamWrapper (Obj-C) to bypass Swift availability checks.

    private func startDisplayStream(displayID: CGDirectDisplayID) {
        guard let _ = self.metalDevice else {
            mlog.error("[ZoneKitVirtualDisplay] No Metal device for stream")
            return
        }

        // Determine capture dimensions from the screen's backing resolution
        let screen = findScreen()
        let scaleFactor = screen?.backingScaleFactor ?? 1.0
        let screenSize = screen?.frame.size ?? CGSize(
            width: CGFloat(configuration.maxWidth),
            height: CGFloat(configuration.maxHeight)
        )
        let pixelWidth = Int(screenSize.width * scaleFactor)
        let pixelHeight = Int(screenSize.height * scaleFactor)

        mlog.debug("[ZoneKitVirtualDisplay] Starting stream: \(pixelWidth)x\(pixelHeight) @ scale \(scaleFactor)")

        // Use Unmanaged to pass `self` as a void* context to the C callback.
        // This retains self for the lifetime of the stream. Released in stopDisplayStream().
        let context = Unmanaged.passRetained(self).toOpaque()

        let stream = ZKDisplayStreamCreate(
            displayID,
            pixelWidth,
            pixelHeight,
            Int32(kCVPixelFormatType_32BGRA),
            configuration.showCursor,
            1.0 / Double(configuration.refreshRate),
            DispatchQueue.main,
            { status, _, frameSurface, _, ctx in
                guard let ctx = ctx else { return }
                let wrapper = Unmanaged<ZoneKitVirtualDisplay>.fromOpaque(ctx).takeUnretainedValue()
                guard status == ZKFrameStatusComplete else { return }
                guard let surface = frameSurface else { return }
                wrapper.handleFrame(surface: surface)
            },
            context
        )

        guard let stream = stream else {
            // Release the retained context on failure
            Unmanaged<ZoneKitVirtualDisplay>.fromOpaque(context).release()
            mlog.error("[ZoneKitVirtualDisplay] Failed to create CGDisplayStream for display \(displayID)")
            return
        }

        let runResult = ZKDisplayStreamStart(stream)
        guard runResult == CGError.success else {
            Unmanaged<ZoneKitVirtualDisplay>.fromOpaque(context).release()
            ZKDisplayStreamRelease(stream)
            mlog.error("[ZoneKitVirtualDisplay] Failed to start CGDisplayStream: \(runResult.rawValue)")
            return
        }

        self.displayStream = stream
        self.streamContext = context
        mlog.info("[ZoneKitVirtualDisplay] Stream started for display \(displayID)")
    }

    private func stopDisplayStream() {
        if let stream = displayStream {
            ZKDisplayStreamStop(stream)
            ZKDisplayStreamRelease(stream)
        }
        displayStream = nil

        // Release the retained context from startDisplayStream
        if let context = streamContext {
            Unmanaged<ZoneKitVirtualDisplay>.fromOpaque(context).release()
            streamContext = nil
        }
    }

    // MARK: - Frame Handling

    /// Receives an IOSurface frame from CGDisplayStream and converts to MTLTexture.
    private func handleFrame(surface: IOSurface) {
        // Deliver raw IOSurface to preview view (if attached)
        onFrameAvailable?(surface)

        guard let texture = createTextureFromIOSurface(surface) else { return }
        guard let source = captureSource else { return }
        delegate?.zoneKitVirtualDisplayDidOutputTexture(texture: texture, source: source)
    }

    /// Zero-copy conversion: binds MTLTexture directly to the IOSurface backing memory.
    private func createTextureFromIOSurface(_ surface: IOSurface) -> MTLTexture? {
        guard let device = metalDevice else { return nil }

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]

        return device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
    }

    // MARK: - Cleanup

    private func tearDown() {
        // Stop retry loop
        retryTimer?.invalidate()
        retryTimer = nil

        // Stop display stream
        stopDisplayStream()

        // Remove screen change observer
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        // Release the virtual display (setting to nil deallocates, removing it from the system)
        virtualDisplay = nil
        displayID = nil
    }
}

#endif
