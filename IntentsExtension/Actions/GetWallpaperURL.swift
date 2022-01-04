//
//  GetWallpaperURL.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/4.
//

import Foundation
import AppKit

@MainActor
final class GetWallpaperURLIntentHandler:NSObject, GetWallpaperUrlIntentHandling, CurrentScreen {
    func handle(intent: GetWallpaperUrlIntent) async -> GetWallpaperUrlIntentResponse {
        let path = getWallpaperPath()
        let response = GetWallpaperUrlIntentResponse(code: path == nil ? .failure : .success, userActivity: nil)
        if let path = path {
            response.wallpaperURL = path.absoluteString.replacingOccurrences(of: "%20", with: " ")
        }
        
        return response
    }
}
