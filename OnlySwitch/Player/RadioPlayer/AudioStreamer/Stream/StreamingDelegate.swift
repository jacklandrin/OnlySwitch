//
//  StreamingDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation

/// The `StreamingDelegate` provides an interface for responding to changes to a `Streaming` instance. These include whenever the streamer state changes, when the download progress changes, as well as the current time and duration changes.
public protocol StreamingDelegate: AnyObject {

    /// Triggered when the downloader fails
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - error: An `Error` representing the reason the download failed
    ///   - url: A `URL` representing the current resource the progress value is for.
    func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL)
    
    /// Triggered when the downloader's progress value changes.
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - progress: A `Float` representing the current progress ranging from 0 - 1.
    ///   - url: A `URL` representing the current resource the progress value is for.
    func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, forURL url: URL)
    
    /// Triggered when the playback `state` changes.
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - state: A `StreamingState` representing the new state value.
    func streamer(_ streamer: Streaming, changedState state: StreamingState)
    
    /// Triggered when the current play time is updated.
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - currentTime: A `TimeInterval` representing the new current time value.
    func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval)
    
    /// Triggered when the duration is updated.
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - duration: A `TimeInterval` representing the new duration value.
    func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval)
    
    /// Triggered when parepare to update next PCMBuffer.
    ///
    /// - Parameters:
    ///   - streamer: The current `Streaming` instance
    ///   - buffer: A `AVAudioPCMBuffer` representing the new duration value.
    func streamer(_ streamer: Streaming, updateBuffer:AVAudioPCMBuffer)
    
    func streamer(_ streamer: Streaming, downloadComplete url: URL)
}
