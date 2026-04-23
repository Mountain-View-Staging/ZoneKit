//
//  VideoMergeTests.swift
//  VideoPlayerKit
//

import XCTest
import AVFoundation
@testable import VideoPlayerKit

final class VideoMergeTests: XCTestCase {

    // MARK: - Initialization

    func testVideoMergeInitialization() {
        let merger = VideoMerge()
        XCTAssertNotNil(merger)
    }

    // MARK: - Error Cases

    func testComposeWithEmptyURLListThrows() async {
        let merger = VideoMerge()
        do {
            _ = try await merger.compose(urls: [])
            XCTFail("Expected VideoMergeError.emptyURLList")
        } catch let error as VideoMergeError {
            if case .emptyURLList = error {
                // Expected
            } else {
                XCTFail("Expected emptyURLList, got: \(error)")
            }
        } catch {
            XCTFail("Expected VideoMergeError, got: \(error)")
        }
    }

    func testComposeWithInvalidURLThrows() async {
        let merger = VideoMerge()
        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/video.mp4")
        do {
            _ = try await merger.compose(urls: [fakeURL])
            XCTFail("Expected error for invalid URL")
        } catch is VideoMergeError {
            // Expected — assetLoadFailed or noVideoTracksFound
        } catch {
            // AVFoundation may throw its own error — also acceptable
        }
    }

    func testVideoMergeErrorCasesAreDistinct() {
        let error1 = VideoMergeError.emptyURLList
        let error2 = VideoMergeError.noVideoTracksFound
        let error3 = VideoMergeError.trackCreationFailed
        let error4 = VideoMergeError.assetLoadFailed(url: URL(fileURLWithPath: "/test.mp4"), description: "test")
        let error5 = VideoMergeError.trackInsertionFailed(url: URL(fileURLWithPath: "/test.mp4"), description: "test")

        let descriptions = [error1, error2, error3, error4, error5].map { "\($0)" }
        let uniqueDescriptions = Set(descriptions)
        XCTAssertEqual(descriptions.count, uniqueDescriptions.count, "All error cases should have distinct descriptions")
    }

    // MARK: - VideoPlayer Integration

    func testLoadMergedVideoDoesNotCrash() {
        let player = VideoPlayer(identifier: "merge-test")
        player.videoPlayerInit()

        // Create a minimal AVPlayerItem (no actual video — just verify no crash)
        let composition = AVMutableComposition()
        let playerItem = AVPlayerItem(asset: composition)

        // Should not crash even with an empty composition
        player.loadMergedVideo(playerItem: playerItem)
    }
}
