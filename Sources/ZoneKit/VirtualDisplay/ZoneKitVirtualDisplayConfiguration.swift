//
//  ZoneKitVirtualDisplayConfiguration.swift
//  ZoneKit
//
//  Created by Dustin Nielson on 2/27/26.
//
//  Configuration for creating virtual displays within ZoneKit.
//  Provides presets for common display configurations.
//

#if os(macOS)

import Foundation
import CoreGraphics

// MARK: - Display Mode

/// A single resolution + refresh rate combination for the virtual display.
public struct ZoneKitDisplayMode: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let refreshRate: CGFloat

    public var size: CGSize { CGSize(width: width, height: height) }
    public var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }

    public init(width: Int, height: Int, refreshRate: CGFloat = 60) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
    }
}

// MARK: - Configuration

/// Configuration for a ZoneKit virtual display.
///
/// Use presets for common configurations, or create a custom configuration
/// for specific display requirements.
public struct ZoneKitVirtualDisplayConfiguration: Sendable {

    // MARK: Display Properties

    /// Display name (visible in System Settings > Displays)
    public var name: String

    /// Maximum pixel width
    public var maxWidth: UInt32

    /// Maximum pixel height
    public var maxHeight: UInt32

    /// Physical size in millimeters (used for DPI calculation)
    public var physicalSizeMillimeters: CGSize

    /// Display vendor identifier
    public var vendorID: UInt32

    /// Display product identifier
    public var productID: UInt32

    /// Display serial number
    public var serialNumber: UInt32

    /// Enable HiDPI (Retina) modes
    public var hiDPIEnabled: Bool

    /// Refresh rate in Hz
    public var refreshRate: CGFloat

    /// Available display modes (resolutions)
    public var displayModes: [ZoneKitDisplayMode]

    // MARK: Capture Options

    /// Whether to show the system cursor in captured frames
    public var showCursor: Bool

    // MARK: Initialization

    public init(
        name: String = "Virtual Display",
        maxWidth: UInt32 = 3840,
        maxHeight: UInt32 = 2160,
        physicalSizeMillimeters: CGSize = CGSize(width: 600, height: 340),
        vendorID: UInt32 = 0x3456,
        productID: UInt32 = 0x1234,
        serialNumber: UInt32 = 0x0001,
        hiDPIEnabled: Bool = true,
        refreshRate: CGFloat = 60,
        displayModes: [ZoneKitDisplayMode]? = nil,
        showCursor: Bool = true
    ) {
        self.name = name
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.physicalSizeMillimeters = physicalSizeMillimeters
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.hiDPIEnabled = hiDPIEnabled
        self.refreshRate = refreshRate
        self.displayModes = displayModes ?? Self.defaultModes(refreshRate: refreshRate)
        self.showCursor = showCursor
    }

    // MARK: Default Modes

    private static func defaultModes(refreshRate: CGFloat) -> [ZoneKitDisplayMode] {
        [
            ZoneKitDisplayMode(width: 3840, height: 2160, refreshRate: refreshRate),
            ZoneKitDisplayMode(width: 2560, height: 1440, refreshRate: refreshRate),
            ZoneKitDisplayMode(width: 1920, height: 1080, refreshRate: refreshRate),
            ZoneKitDisplayMode(width: 1280, height: 720, refreshRate: refreshRate),
        ]
    }
}

// MARK: - Presets

public extension ZoneKitVirtualDisplayConfiguration {

    /// 1920x1080 landscape (16:9)
    static var preset1080p: ZoneKitVirtualDisplayConfiguration {
        ZoneKitVirtualDisplayConfiguration(
            name: "Virtual Display",
            maxWidth: 1920,
            maxHeight: 1080,
            displayModes: [
                ZoneKitDisplayMode(width: 1920, height: 1080),
                ZoneKitDisplayMode(width: 1280, height: 720),
            ]
        )
    }

    /// 1080x1920 portrait (9:16)
    static var preset1080pPortrait: ZoneKitVirtualDisplayConfiguration {
        ZoneKitVirtualDisplayConfiguration(
            name: "Virtual Display",
            maxWidth: 1080,
            maxHeight: 1920,
            displayModes: [
                ZoneKitDisplayMode(width: 1080, height: 1920),
                ZoneKitDisplayMode(width: 720, height: 1280),
            ]
        )
    }

    /// 3840x2160 landscape (16:9) with fallback modes
    static var preset4K: ZoneKitVirtualDisplayConfiguration {
        ZoneKitVirtualDisplayConfiguration(
            name: "Virtual Display",
            maxWidth: 3840,
            maxHeight: 2160,
            displayModes: [
                ZoneKitDisplayMode(width: 3840, height: 2160),
                ZoneKitDisplayMode(width: 2560, height: 1440),
                ZoneKitDisplayMode(width: 1920, height: 1080),
            ]
        )
    }

    /// 2160x3840 portrait (9:16) with fallback modes
    static var preset4KPortrait: ZoneKitVirtualDisplayConfiguration {
        ZoneKitVirtualDisplayConfiguration(
            name: "Virtual Display",
            maxWidth: 2160,
            maxHeight: 3840,
            displayModes: [
                ZoneKitDisplayMode(width: 2160, height: 3840),
                ZoneKitDisplayMode(width: 1440, height: 2560),
                ZoneKitDisplayMode(width: 1080, height: 1920),
            ]
        )
    }
}

#endif
