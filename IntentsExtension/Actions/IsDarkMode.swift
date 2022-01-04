//
//  IsDarkMode.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/4.
//

import Foundation

@MainActor
final class IsDarkModeIntentHandler:NSObject, IsDarkModeIntentHandling {
    func handle(intent: IsDarkModeIntent) async -> IsDarkModeIntentResponse {
        let response = IsDarkModeIntentResponse(code: .success, userActivity: nil)
        let isDarkMode = currentInferfaceStyle.runAppleScript(isShellCMD: true).1 as! String == "Dark"
        response.isDarkMode = isDarkMode as NSNumber
        return response
    }
}
