//
//  StreamingState.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation

/// The various playback states of a `Streaming`.
///
/// - stopped: Audio playback and download operations are all stopped
/// - paused: Audio playback is paused
/// - playing: Audio playback is playing
public enum StreamingState: String {
    case stopped
    case paused
    case playing
}
