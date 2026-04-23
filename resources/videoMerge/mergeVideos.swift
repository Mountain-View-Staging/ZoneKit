//
//  mergeVideos.swift
//  MVS Marquee
//
//  Created by Dustin Nielson on 5/24/25.
//

import Foundation
import AVFoundation

class mergeVideos:NSObject {
    
    var player: AVPlayer?
    
//    func startMerge() {
//        let semaphore = DispatchSemaphore(value: 0)
//        Task {
//            await self.setupVideos()
//            semaphore.signal()
//        }
//        semaphore.wait()
//    }
    
    func setupVideos() {
        let movie = AVMutableComposition()
        let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let mediaPath1 = URL(fileURLWithPath:Bundle.main.path(forResource: "BH1", ofType: "mp4")!)
        let mediaPath2 = URL(fileURLWithPath:Bundle.main.path(forResource: "BH2", ofType: "mp4")!)
        
        let videoAsset1 = AVURLAsset(url: mediaPath1)
        let videoAsset2 = AVURLAsset(url: mediaPath2)
        
        mergeVideos(videoAsset1: videoAsset1, videoAsset2: videoAsset2)
    }
    
    func mergeVideos(videoAsset1: AVAsset, videoAsset2: AVAsset)  {
        let movie = AVMutableComposition()
        let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        Task {
            do {
                var currentDuration = movie.duration
                
                let video1Range = await CMTimeRangeMake(start: CMTime.zero, duration: try videoAsset1.load(.duration))
                let video1AudioTrack = try await videoAsset1.loadTracks(withMediaType: .audio).first!
                let video1VideoTrack = try await videoAsset1.loadTracks(withMediaType: .video).first!
                
                try videoTrack?.insertTimeRange(video1Range, of: video1VideoTrack, at: currentDuration)
                try audioTrack?.insertTimeRange(video1Range, of: video1AudioTrack, at: currentDuration)
                videoTrack?.preferredTransform = try await video1VideoTrack.load(.preferredTransform)
                currentDuration = movie.duration
                
                let video2Range = await CMTimeRangeMake(start: CMTime.zero, duration: try videoAsset2.load(.duration))
                let video2AudioTrack = try await videoAsset2.loadTracks(withMediaType: .audio).first!
                let video2VideoTrack = try await videoAsset2.loadTracks(withMediaType: .video).first!
                
                try videoTrack?.insertTimeRange(video2Range, of: video2VideoTrack, at: currentDuration)
                
                try videoTrack?.insertTimeRange(video2Range, of: video2VideoTrack, at: currentDuration)
                try audioTrack?.insertTimeRange(video2Range, of: video2AudioTrack, at: currentDuration)
                videoTrack?.preferredTransform = try await video2VideoTrack.load(.preferredTransform)
                currentDuration = movie.duration
                
                //player = await AVPlayer(playerItem: AVPlayerItem(asset: movie))
                
                export(movie)
            } catch {
                
            }
        }
        
        
    }
    
    func export(_ asset: AVAsset) {
        
        guard let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("exported.mov") else { return }

        //delete any old file
        do {
          try FileManager.default.removeItem(at: outputMovieURL)
        } catch {
          print("Could not remove file (or file doesn't exist) \(error.localizedDescription)")
        }

        //create exporter
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)

        //configure exporter
        exporter?.outputURL = outputMovieURL
        exporter?.outputFileType = .mov

        //export!
        exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
          DispatchQueue.main.async {
            if let error = exporter?.error {
              print("failed \(error.localizedDescription)")
            } else {
                print("Successfully exported video")
            }
          }

        })
      }
    
}
