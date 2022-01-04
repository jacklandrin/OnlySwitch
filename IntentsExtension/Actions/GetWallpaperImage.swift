//
//  GetImage.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/3.
//

import Foundation
import Intents
import AppKit

@MainActor
final class GetWallpaperImageIntentHandler:NSObject, GetWallpaperImageIntentHandling, CurrentScreen {
    func handle(intent: GetWallpaperImageIntent) async -> GetWallpaperImageIntentResponse {
        let path = getWallpaperPath()
        let response = GetWallpaperImageIntentResponse(code: path == nil ? .failure : .success, userActivity: nil)
        if let path = path {
            let image = NSImage(contentsOf: path)
            response.image = image?.toINFile
        }
        
        return response
    }
    
}
