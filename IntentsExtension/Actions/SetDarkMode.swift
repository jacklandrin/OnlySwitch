//
//  SetDarkMode.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/4.
//

import Foundation
import Switches

@MainActor
final class SetDarkModeIntentHandler:NSObject, SetDarkModeIntentHandling {
    func handle(intent: SetDarkModeIntent) async -> SetDarkModeIntentResponse {
        let response = SetDarkModeIntentResponse(code: .success, userActivity: nil)
        do {
            if intent.State?.boolValue == true {
                _ = try DarkModeCMD.on.runAppleScript()
            } else {
                _ = try DarkModeCMD.off.runAppleScript()
            }
        } catch {
            
        }
        
        return response
    }
}
