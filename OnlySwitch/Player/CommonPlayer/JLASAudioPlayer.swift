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

class JLASAudioPlayer: NSObject, AVPlayerItemMetadataOutputPushDelegate, AudioPlayer {
    
    let queue = DispatchQueue(label: "com.springRadio.spectrum")
    lazy var audioPlayer: Streamer = {
        let audioPlayer = Streamer()
        audioPlayer.delegate = self
        return audioPlayer
    }()
    
    weak var currentPlayerItem: CommonPlayerItem?
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
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: self.avplayer.currentItem, queue: .main) { [weak self] _ in
            guard self?.currentPlayerItem?.type == .BackNoises else {
                return
            }
            self?.avplayer.seek(to: CMTime.zero)
            self?.avplayer.play()
        }
    }
    
    func play(stream item: CommonPlayerItem) {
        guard let url = item.url else {
            return
        }
               
        if let currentPlayerItem = currentPlayerItem {
            if currentPlayerItem.url?.absoluteURL != item.url?.absoluteURL {
                self.currentPlayerItem?.isPlaying = false
                self.currentPlayerItem?.trackInfo = ""
                if currentPlayerItem.type != item.type {
                    switch currentPlayerItem.type {
                    case .Radio:
                        NotificationCenter.default.post(name: .refreshSingleSwitchStatus,
                                                        object: SwitchType.radioStation)
                    case .BackNoises:
                        NotificationCenter.default.post(name: .refreshSingleSwitchStatus,
                                                        object: SwitchType.backNoises)
                    }
                    
                }
            } 
        }
                
        self.currentPlayerItem = item
        
        
        setAVPlayer(url: url, itemType: item.type)
        audioPlayer.url = url
        if avplayerMute(url: url.absoluteString, itemType: item.type) {
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
    
    func avplayerMute(url:String, itemType: PlayerType) -> Bool {
        itemType == .Radio && wavableURL(url: url)
    }
    
    func setAVPlayer(url:URL, itemType:PlayerType)  {
        let playerItem = AVPlayerItem(url: url)
        playerItem.audioTimePitchAlgorithm = itemType == .BackNoises ? .varispeed : .spectral
        self.avplayer = AVPlayer(playerItem: playerItem)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        playerItem.add(metadataOutput)
        
        self.audioPlayer.volume = Preferences.shared.volume
        self.avplayer.volume = Preferences.shared.volume
        
        self.avplayer.play()
        self.avplayer.isMuted = avplayerMute(url: url.absoluteString, itemType: itemType)
    }
    
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let item = groups.first?.items.first, let title = item.value(forKeyPath: "value") as? String else {
            let currentTitle = self.currentPlayerItem?.trackInfo
            self.currentPlayerItem?.trackInfo = currentTitle ?? ""
            return
        }
        withAnimation(.default) {
            self.currentPlayerItem?.trackInfo = title.trimmingCharacters(in:.newlines)
        }
        self.updateStreamInfo(info: self.currentPlayerItem?.trackInfo)
    }
    
    func stop() {
        audioPlayer.stop()
        avplayer.stop()
        pauseCommandCenter()
    }
    
    func pause() {
        audioPlayer.pause()
        avplayer.pause()
        pauseCommandCenter()
    }
    
    deinit {
        
    }
}

