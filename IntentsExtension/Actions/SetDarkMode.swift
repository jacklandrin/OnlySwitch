//
//  SetDarkMode.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/4.
//

import Foundation

@MainActor
final class SetDarkModeIntentHandler:NSObject, SetDarkModeIntentHandling {
    func handle(intent: SetDarkModeIntent) async -> SetDarkModeIntentResponse {
        let response = SetDarkModeIntentResponse(code: .success, userActivity: nil)
        if intent.State?.boolValue == true {
//            UserDefaults.standard.set("Light", forKey: "AppleInterfaceStyle")
            _ = turnOnDarkModeCMD.runAppleScript()
        } else {
//            UserDefaults.standard.set("Dark", forKey: "AppleInterfaceStyle")
           _ = turnOffDarkModeCMD.runAppleScript()
        }
//        UserDefaults.standard.synchronize()
        return response
    }
}
