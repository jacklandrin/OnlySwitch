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

let bufferSize = 512

class JLASAudioPlayer: NSObject, AudioPlayer, AVPlayerItemMetadataOutputPushDelegate {
    let queue = DispatchQueue(label: "com.springRadio.spectrum")
    lazy var audioPlayer: Streamer = {
        let audioPlayer = Streamer()
        audioPlayer.delegate = self
        return audioPlayer
    }()
    var currentAudioStation: RadioPlayerItem?
    var analyzer:RealtimeAnalyzer = RealtimeAnalyzer(fftSize: bufferSize)
    var bufferring:Bool = false
    
    private var avplayer: AVPlayer = AVPlayer()
    public internal(set) var isAppActive = true
    
    override init() {
        super.init()
        self.setupRemoteCommandCenter()
        NotificationCenter.default.addObserver(forName: showPopoverNotificationName, object: nil, queue: .main, using: { _ in
            self.isAppActive = true
        })

        NotificationCenter.default.addObserver(forName: hidePopoverNotificationName, object: nil, queue: .main, using: { _ in
            self.isAppActive = false
        })
    }
    
    func play(stream item: RadioPlayerItem) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.audioPlayer.play()
        }
        self.bufferring = true
       
        self.setupNowPlaying()
    }
    
    func setAVPlayer(url:URL)  {
        let playerItem = AVPlayerItem(url: url)
        self.avplayer = AVPlayer(playerItem: playerItem)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        playerItem.add(metadataOutput)
        self.avplayer.play()
        self.avplayer.isMuted = true
    }
    
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let item = groups.first?.items.first, let title = item.value(forKeyPath: "value") as? String else {
            let currentStationTitle = self.currentAudioStation?.streamInfo
            self.currentAudioStation?.streamInfo = currentStationTitle ?? ""
            return
        }
        self.currentAudioStation?.streamInfo = title.trimmingCharacters(in:.newlines)
    }
    
    func stop() {
        audioPlayer.stop()
        avplayer.stop()
    }
    
    
}
