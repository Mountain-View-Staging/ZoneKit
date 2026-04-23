//
//  VideoPlayer.swift
//  Metal Composite Test
//
//  Created by MVS on 4/12/25.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif
import AVFoundation

protocol VideoPlayerDelegate: AnyObject {
    
    func VideoPlayerBuffer(pixelBuffer: CVPixelBuffer)
}

class VideoPlayer: NSObject {
    
    weak var delegate: VideoPlayerDelegate?
    
    var player:AVPlayer? = AVPlayer()
    var playerLooper: AVPlayerLooper?
    var playerItem:AVPlayerItem?
    
    var videoOutput:AVPlayerItemVideoOutput?
    
    var videoUrl: URL?  {
        didSet{
            guard let videoUrl else {
                stopVideo()
                return
            }
            print("VideoPlayer :: videoUrl \(videoUrl)")
            //loopVideo()
        }
    }
    
    var videoClips = [AVAsset]()
    
    let videoComposition = AVMutableComposition()
    var lastTime: CMTime = CMTime.zero
    
    var playerIsPause:Bool = false {
        didSet {}
    }
    
    convenience init(delegate: VideoPlayerDelegate) {
        self.init()
        self.delegate = delegate
        videoPlayerInit()
    }
    
    deinit {
        print("VideoPlayer deinit")
        stopVideo()
        if player != nil {
            player!.replaceCurrentItem(with: nil)
        }
        
        player = nil
        
    }
    
    func videoPlayerInit(){ //self.player.currentItem
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] vidObjItem in
            
            guard let vItem = vidObjItem.object as! AVPlayerItem? else { return }
            guard let player = self?.player else { return }
            if vItem == player.currentItem {
                player.seek(to: CMTime.zero)
                player.play()
            }
        }
        
        //let pixelFormat:PixelFormat = .
        guard let player else { return }
        
        videoOutput = {
            let v = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
                String(kCVPixelBufferMetalCompatibilityKey): true
            ])
            return v
        }()
        
        player.volume = 1.0
        
        player.isMuted = false
        
        player.actionAtItemEnd = .none
        
        //mergeVideos()
        
        print("//** Video Player Init")
    }
    
//    func mergeVideos(videoAsset1: AVAsset, videoAsset2: AVAsset)  {
    func mergeVideos(urlList: [URL])  {
        
        videoClips = [AVAsset]()
        
        urlList.forEach { URL in
            videoClips.append(AVURLAsset(url: URL))
        }
        
        Task {
            do {
                let videoCompositionVideoTrack = videoComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
                let videoCompositionAudioTrack = videoComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
                
                for clipIndex in videoClips {
                    
                    if try await clipIndex.loadTracks(withMediaType: AVMediaType.video).count > 0 {
                        try await videoCompositionVideoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: clipIndex.load(.duration)),
                                                                              of: clipIndex.loadTracks(withMediaType: AVMediaType.video).first! ,
                                                                              at: lastTime)
                    }
                    if try await clipIndex.loadTracks(withMediaType: AVMediaType.audio).count > 0 {
                        try await videoCompositionAudioTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: clipIndex.load(.duration)),
                                                                              of: clipIndex.loadTracks(withMediaType: AVMediaType.audio).first! ,
                                                                              at: lastTime)
                    }
                    
                    lastTime = await CMTimeAdd(lastTime, try clipIndex.load(.duration))
                    
                }
                
                let playerItem = await AVPlayerItem(asset: videoComposition)
                await playerItem.add(videoOutput!)
                
                print("DEBUG :: SHOULD HAV CLEAN VIDEO LOOP *****************************************")
                
                loopVideo(videoItem: playerItem)
                

                
                
            } catch {
                print("VideoPlayer :: mergeVideos :: Error \(error.localizedDescription)")
            }
        }
        
        
    }
    
    func export(_ asset: AVAsset) {
        
        guard let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("exportedx.mov") else { return }
        print(outputMovieURL)
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
    
    
    func loopVideo(videoItem: AVPlayerItem){
        guard let player else { return }
        
        print(videoItem)
        
       // guard videoUrl != nil else { return }
        
        //let duration = Int64( ( (Float64(CMTimeGetSeconds(AVAsset(url: videoUrl!).duration)) *  10.0) - 1) / 10.0 )
        
       // let videoItem = AVPlayerItem(url: videoUrl!)
        
        videoItem.add(videoOutput!)
        
        videoItem.preferredForwardBufferDuration = TimeInterval(1)
        
        player.replaceCurrentItem(with: videoItem)
        
        player.seek(to: CMTime.zero)
        
        player.play()
        
}
    
    func stopVideo(pausePlayer:Bool = false){
        guard let player else { return }
        player.pause()
    }
    
    func indirectBufferCheck() {
        guard let videoOutput, let player else { return }
        if videoOutput.hasNewPixelBuffer(forItemTime: player.currentTime()) {
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) {
               delegate?.VideoPlayerBuffer(pixelBuffer: pixelBuffer)
            } else {
                print("//** Cant convert pixelbuffer")
            }
        }
    }
    
    func directBufferCheck() -> CVPixelBuffer? {
        guard let videoOutput, let player else { return nil }
        if videoOutput.hasNewPixelBuffer(forItemTime: player.currentTime()) {
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) {
               return pixelBuffer
            } else {
                print("//** Cant convert pixelbuffer")
                return nil
            }
        } else {
            return nil
        }
    }
}


