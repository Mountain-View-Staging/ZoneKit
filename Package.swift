// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZoneKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v16),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "ZoneKit",
            targets: ["ZoneKit"]
        ),
        // Core layout calculation engine — Foundation + CoreGraphics only
        .library(
            name: "ZoneLayoutGenerator",
            targets: ["ZoneLayoutGenerator"]
        ),
        // Metal-based compositing engine — requires Metal + MPS
        .library(
            name: "TextureCompositorEngine",
            targets: ["TextureCompositorEngine"]
        ),
        // Video-to-texture extraction — AVFoundation-based video playback
        .library(
            name: "VideoPlayerKit",
            targets: ["VideoPlayerKit"]
        ),
    ],
    dependencies: [
        .package(path: "../MarqueeFoundation"),
        .package(path: "../MarqueeShaderKit"),
        .package(path: "../LoggingKit"),
    ],
    targets: [
        .target(
            name: "CZoneKitVirtualDisplayPrivate",
            path: "Sources/CZoneKitVirtualDisplayPrivate"
        ),

        // MARK: - Core Layout Calculator
        // Foundation + CoreGraphics only — no Metal dependency.
        // Can be imported standalone for layout calculation without GPU.
        .target(
            name: "ZoneLayoutGenerator",
            dependencies: ["MarqueeFoundation", "LoggingKit"],
            path: "Sources/ZoneLayoutGenerator"
        ),

        // MARK: - Metal Composite Engine
        // Shaders are provided by MarqueeShaderKit via dependency injection.
        // The consuming app resolves the MTLLibrary and passes it in.
        .target(
            name: "TextureCompositorEngine",
            dependencies: ["ZoneLayoutGenerator", "MarqueeShaderKit", "LoggingKit"],
            path: "Sources/TextureCompositorEngine"
        ),

        // MARK: - Video Player
        // AVFoundation-based video frame extraction with Metal-compatible CVPixelBuffer output.
        .target(
            name: "VideoPlayerKit",
            dependencies: ["LoggingKit"],
            path: "Sources/VideoPlayerKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Full Capture Stack
        // Re-exports ZoneLayoutGenerator, TextureCompositorEngine, and VideoPlayerKit for backward compatibility.
        .target(
            name: "ZoneKit",
            dependencies: [
                "ZoneLayoutGenerator",
                "TextureCompositorEngine",
                "VideoPlayerKit",
                "MarqueeFoundation",
                "LoggingKit",
                "MarqueeShaderKit",
                .target(name: "CZoneKitVirtualDisplayPrivate", condition: .when(platforms: [.macOS])),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
