//
//  Downloader+URLSessionDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import os.log

extension Downloader: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
//        os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)

        totalBytesCount = response.expectedContentLength
//        print("totalBytesCount:\(totalBytesCount)")
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
//        os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line, data.count)
        let response = dataTask.response
//        print("\(String(describing: response?.mimeType))")
        if response?.mimeType == "audio/x-scpls" {
            
        } else if response?.mimeType == "audio/mpeg" || response?.mimeType == "audio/aacp"{
            totalBytesReceived += Int64(data.count)
            progress = Float(totalBytesReceived) / Float(totalBytesCount)
//            print("totalBytesReceived:\(totalBytesReceived)")
            delegate?.download(self, didReceiveData: data, progress: progress)
            progressHandler?(data, progress)
        } else  {
            print("other response:\(String(describing: response))")
        }
        
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)
        var networkError = error
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        if networkError == nil && statusCode != 200 {
             networkError = NSError(domain:"", code: statusCode!, userInfo: nil)
        }
        state = .completed
        delegate?.download(self, completedWithError: error)
        completionHandler?(error)
    }
}
