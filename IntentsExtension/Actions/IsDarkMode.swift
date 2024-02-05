//
//  IsDarkMode.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/4.
//

import Foundation
import Switches

@MainActor
final class IsDarkModeIntentHandler:NSObject, IsDarkModeIntentHandling {
    func handle(intent: IsDarkModeIntent) async -> IsDarkModeIntentResponse {
        let response = IsDarkModeIntentResponse(code: .success, userActivity: nil)
        do {
            let isDarkMode = try DarkModeCMD.status.runAppleScript(isShellCMD: true) == "Dark"
            response.isDarkMode = isDarkMode as NSNumber
        } catch {
            
        }
        
        return response
    }
}
