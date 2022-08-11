//
//  JLAVAudioPlayer.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import AVFoundation
import AVKit
import MediaPlayer

class JLAVAudioPlayer: NSObject ,AVPlayerItemMetadataOutputPushDelegate, AudioPlayer {
    
    var audioPlayer: AVPlayer?
    var playerItem: AVPlayerItem?
    weak var currentPlayerItem: CommonPlayerItem?
    var analyzer = RealtimeAnalyzer(fftSize: bufferSize)
    var bufferring: Bool = false
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .volumeChange, object: nil, queue: .main, using: { notification in
            guard let userInfo = notification.userInfo,
                    let newValue  = userInfo["newValue"] as? Float else {
                        print("No userInfo found in notification")
                        return
                }
            
            self.audioPlayer?.volume = newValue
        })
    }
    
    func play(stream item: CommonPlayerItem) {
        
        guard let url = item.url else {
            return
        }
        
        if let item = self.currentPlayerItem  {
            if item.url?.absoluteString != url.absoluteString {
                self.currentPlayerItem?.isPlaying = false
                self.currentPlayerItem?.trackInfo = ""
            }
        }
        
        self.currentPlayerItem = item
        
        self.audioPlayer?.stop()
        
        let asset = AVAsset(url: url)
        
        self.playerItem = AVPlayerItem(asset: asset)
        self.audioPlayer = AVPlayer(playerItem: playerItem)
        self.audioPlayer?.play()
        self.audioPlayer?.volume = Preferences.shared.volume
        self.bufferring = true
        
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        self.playerItem?.add(metadataOutput)
    }
    
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let item = groups.first?.items.first, let title = item.value(forKeyPath: "value") as? String else {
            let title = self.currentPlayerItem?.trackInfo ?? ""
            self.currentPlayerItem?.trackInfo = title
            return
        }
        self.currentPlayerItem?.trackInfo = title.trimmingCharacters(in:.newlines)
        self.bufferring = false
        self.updateStreamInfo(info: self.currentPlayerItem?.trackInfo)
    }
    
    func stop(){
        self.audioPlayer?.stop()
        pauseCommandCenter()
    }
    
    func pause() {
        self.audioPlayer?.pause()
        pauseCommandCenter()
    }
}

extension AVPlayer {
    func stop() {
        self.seek(to: CMTime.zero)
        self.pause()
        self.replaceCurrentItem(with: nil)
    }
}
