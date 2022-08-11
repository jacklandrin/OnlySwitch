//
//  Downloading.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation

/// The `Downloading` protocol represents a generic downloader that can be used for grabbing a fixed length audio file.
public protocol Downloading: AnyObject {
    
    // MARK: - Properties
    
    /// A receiver implementing the `DownloadingDelegate` to receive state change, completion, and progress events from the `Downloading` instance.
    var delegate: DownloadingDelegate? { get set }
    
    /// A completion block for when the contents of the download are fully downloaded.
    var completionHandler: ((Error?) -> Void)? { get set }
    
    /// The current progress of the downloader. Ranges from 0.0 - 1.0, default is 0.0.
    var progress: Float { get }
    
    /// The current state of the downloader. See `DownloadingState` for the different possible states.
    var state: DownloadingState { get }
    
    /// A `URL` representing the current URL the downloader is fetching. This is an optional because this protocol is designed to allow classes implementing the `Downloading` protocol to be used as singletons for many different URLS so a common cache can be used to redownloading the same resources.
    var url: URL? { get set }
    
    // MARK: - Methods
    
    /// Starts the downloader
    func start()
    
    /// Pauses the downloader
    func pause()
    
    /// Stops and/or aborts the downloader. This should invalidate all cached data under the hood.
    func stop()
    
}
