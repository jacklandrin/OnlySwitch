//
//  DownloadingState.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation

/// The various states of a download request.
///
/// - completed: The download has completed
/// - started: The download has yet to start
/// - paused: The download is paused
/// - notStarted: The download has not started yet
/// - stopped: The download has been stopped/cancelled
public enum DownloadingState: String {
    case completed
    case started
    case paused
    case notStarted
    case stopped
}
