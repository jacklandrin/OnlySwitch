//
//  JLASAudioPlayer+Streamer.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import Foundation
import AVFoundation



extension JLASAudioPlayer : StreamingDelegate {
    func streamer(_ streamer: Streaming, downloadComplete url: URL) {
        self.audioPlayer.play()
    }
    
    
    func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL) {
        if let error = error as? MimeTypeError, error == .unsupportedFormat {
            self.audioPlayer.stop()
            self.avplayer.isMuted = false
            return
        }
        if url == self.audioPlayer.url && self.currentPlayerItem!.isPlaying {
            self.audioPlayer.play()
        } else {
            guard let currentUrl = self.currentPlayerItem?.url else {
                self.audioPlayer.stop()
                return
            }
            if error.localizedDescription == "cancelled" && currentUrl.absoluteString == url.absoluteString {
//                self.audioPlayer.stop()
                self.currentPlayerItem!.isPlaying = false
            } else {
                self.audioPlayer.play()
            }
        }
    }
    
    func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, forURL url: URL) {
        
    }
    
    func streamer(_ streamer: Streaming, changedState state: StreamingState) {
        
    }
    
    func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval) {
        
    }
    
    func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval) {
        
    }
    
    func streamer(_ streamer: Streaming, updateBuffer: AVAudioPCMBuffer) {
        guard self.isAppActive else {
            return
        }
        let buffer = updateBuffer
        let spectra = self.analyzer.analyse(with: buffer)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .spectra, object: spectra)
        }

        self.bufferring = false
    }
    
    
}

