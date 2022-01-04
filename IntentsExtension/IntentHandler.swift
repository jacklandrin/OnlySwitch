//
//  IntentHandler.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/3.
//

import Intents

@MainActor
class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any? {
        switch intent {
        case is GetWallpaperImageIntent:
            return GetWallpaperImageIntentHandler()
        case is GetWallpaperUrlIntent:
            return GetWallpaperURLIntentHandler()
        case is IsDarkModeIntent:
            return IsDarkModeIntentHandler()
        case is SetDarkModeIntent:
            return SetDarkModeIntentHandler()
        default:
            assertionFailure("No handler for this intent")
            return nil
        }
    
    }
    
}
