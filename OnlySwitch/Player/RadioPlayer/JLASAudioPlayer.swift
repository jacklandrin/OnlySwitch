//
//  JLASAudioPlayer.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI

let bufferSize = 512

class JLASAudioPlayer: NSObject, AudioPlayer, AVPlayerItemMetadataOutputPushDelegate {
    let queue = DispatchQueue(label: "com.springRadio.spectrum")
    lazy var audioPlayer: Streamer = {
        let audioPlayer = Streamer()
        audioPlayer.delegate = self
        return audioPlayer
    }()
    weak var currentAudioStation: RadioPlayerItemViewModel?
    var analyzer:RealtimeAnalyzer = RealtimeAnalyzer(fftSize: bufferSize)
    var bufferring:Bool = false
    
    var avplayer: AVPlayer = AVPlayer()
    public internal(set) var isAppActive = false
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .showPopover,
                                               object: nil,
                                               queue: .main,
                                               using: { _ in
            self.isAppActive = true
        })

        NotificationCenter.default.addObserver(forName: .hidePopover,
                                               object: nil,
                                               queue: .main,
                                               using: { _ in
            self.isAppActive = false
        })
        
        NotificationCenter.default.addObserver(forName: .volumeChange,
                                               object: nil,
                                               queue: .main,
                                               using: { notification in
            guard let userInfo = notification.userInfo,
                    let newValue  = userInfo["newValue"] as? Float else {
                        print("No userInfo found in notification")
                        return
                }
            
            self.audioPlayer.volume = newValue
            self.avplayer.volume = newValue
        })
    }
    
    func play(stream item: RadioPlayerItemViewModel) {
        guard let url = URL(string: item.streamUrl) else {
            return
        }
               
        if let currentAudioStation = currentAudioStation {
            if currentAudioStation.streamUrl != item.streamUrl {
                self.currentAudioStation?.isPlaying = false
                self.currentAudioStation?.streamInfo = ""
            }
        }
                
        self.currentAudioStation = item
        
        
        setAVPlayer(url: url)
        audioPlayer.url = url
        if wavableURL(url: url.absoluteString) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.audioPlayer.play()
            }
        }
        
        self.bufferring = true
       
        self.setupNowPlaying()
    }
    
    func wavableURL(url:String) -> Bool {
        return !url.hasSuffix(".m3u") && !url.hasSuffix(".m3u8") && !url.hasSuffix(".aac")
    }
    
    func setAVPlayer(url:URL)  {
        let playerItem = AVPlayerItem(url: url)
        self.avplayer = AVPlayer(playerItem: playerItem)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        playerItem.add(metadataOutput)
        
        self.audioPlayer.volume = Preferences.shared.volume
        self.avplayer.volume = Preferences.shared.volume
        
        self.avplayer.play()
        self.avplayer.isMuted = wavableURL(url: url.absoluteString)
    }
    
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let item = groups.first?.items.first, let title = item.value(forKeyPath: "value") as? String else {
            let currentStationTitle = self.currentAudioStation?.streamInfo
            self.currentAudioStation?.streamInfo = currentStationTitle ?? ""
            return
        }
        withAnimation(.default) {
            self.currentAudioStation?.streamInfo = title.trimmingCharacters(in:.newlines)
        }
        self.updateStreamInfo(info: self.currentAudioStation?.streamInfo)
    }
    
    func stop() {
        audioPlayer.stop()
        avplayer.stop()
        pauseCommandCenter()
    }
    
    deinit {
        
    }
}
