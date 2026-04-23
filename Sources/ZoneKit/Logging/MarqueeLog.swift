//
//  MarqueeLog.swift
//  ZoneKit
//
import OSLog
import LoggingKit

// MARK: - Module-level instance

let mlog = MarqueeLog(
    logger: Logger(subsystem: "com.mvsmarquee.ZoneKit", category: "ZoneKit"),
    projectTag: "ZoneKit"
)
