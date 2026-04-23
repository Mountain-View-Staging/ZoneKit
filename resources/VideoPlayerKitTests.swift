//
//  VideoPlayerKitTests.swift
//  VideoPlayerKit
//

import XCTest
@testable import VideoPlayerKit

/// Test delegate to verify protocol conformance
private class TestVideoPlayerDelegate: VideoPlayerDelegate {
    var lastIdentifier: String?
    var bufferCallCount = 0

    func VideoPlayerBuffer(pixelBuffer: CVPixelBuffer?) {
        bufferCallCount += 1
    }

    func videoPlayerDidCompleteLoop(identifier: String) {
        lastIdentifier = identifier
    }
}

final class VideoPlayerKitTests: XCTestCase {

    func testVideoPlayerInitialization() {
        let player = VideoPlayer(identifier: "test-player")
        XCTAssertEqual(player.identifier, "test-player")
        XCTAssertNotNil(player.player)
    }

    func testVideoPlayerDelegateConformance() {
        let delegate = TestVideoPlayerDelegate()
        let player = VideoPlayer(identifier: "delegate-test")
        player.delegate = delegate

        XCTAssertNotNil(player.delegate)
    }

    func testVideoPlayerStopWithoutPlay() {
        let player = VideoPlayer(identifier: "stop-test")
        // Should not crash when stopping without having started
        player.stopVideo(pausePlayer: true)
    }
}
