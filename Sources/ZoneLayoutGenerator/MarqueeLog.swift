//
//  MarqueeLog.swift
//  ZoneLayoutGenerator
//
import OSLog
import LoggingKit

// MARK: - Module-level instance

let mlog = MarqueeLog(
    logger: Logger(subsystem: "com.mvsmarquee.ZoneKit", category: "ZoneLayoutGenerator"),
    projectTag: "ZoneLayoutGenerator"
)
