//
//  Streamer+DownloadingDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import os.log

extension Streamer: DownloadingDelegate {
    
    public func download(_ download: Downloading, completedWithError error: Error?) {
        os_log("%@ - %d [error: %@]", log: Streamer.logger, type: .debug, #function, #line, String(describing: error?.localizedDescription))
        
        if let error = error, let url = download.url {
            DispatchQueue.main.async { [unowned self] in
                self.delegate?.streamer(self, failedDownloadWithError: error, forURL: url)
            }
        } else if let url = download.url {
            DispatchQueue.main.async { [unowned self] in
                self.delegate?.streamer(self, downloadComplete: url)
            }
        }
    }
    
    public func download(_ download: Downloading, changedState downloadState: DownloadingState) {
        os_log("%@ - %d [state: %@]", log: Streamer.logger, type: .debug, #function, #line, String(describing: downloadState))
//        if downloadState == .completed {
//            download.start()
//        }
    }
    
    public func download(_ download: Downloading, didReceiveData data: Data, progress: Float) {
//        os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
        
        guard let parser = parser else {
            os_log("Expected parser, bail...", log: Streamer.logger, type: .error)
            return
        }
        
        /// Parse the incoming audio into packets
        do {
            try parser.parse(data: data)
        } catch {
            os_log("Failed to parse: %@", log: Streamer.logger, type: .error, error.localizedDescription)
        }
        
        /// Once there's enough data to start producing packets we can use the data format
        if reader == nil, let _ = parser.dataFormat {
            do {
                reader = try Reader(parser: parser, readFormat: readFormat)
            } catch {
                os_log("Failed to create reader: %@", log: Streamer.logger, type: .error, error.localizedDescription)
            }
        }
        
        /// Update the progress UI
        DispatchQueue.main.async {
            [weak self] in
            
            // Notify the delegate of the new progress value of the download
            self?.notifyDownloadProgress(progress)
            
            // Check if we have the duration
            self?.handleDurationUpdate()
        }
    }
    
}
