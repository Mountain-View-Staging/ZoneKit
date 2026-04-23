//
//  MarqueeLog.swift
//  VideoPlayerKit
//
import OSLog
import LoggingKit

// MARK: - Module-level instance

let mlog = MarqueeLog(
    logger: Logger(subsystem: "com.mvsmarquee.VideoPlayerKit", category: "VideoPlayerKit"),
    projectTag: "VideoPlayerKit"
)
