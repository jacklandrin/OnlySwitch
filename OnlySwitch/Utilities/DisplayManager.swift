//
//  DisplayManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import Foundation

class DisplayManager{
    private var displayIDs:[CGDirectDisplayID] = []
    
    private var builtInDisplayID:CGDirectDisplayID? {
        displayIDs.filter{ self.isAppleDisplay(displayID: $0) }.first
    }
    
    var existBuiltInDisplay:Bool {
        builtInDisplayID != nil
    }
    
    func clearDisplays() {
        self.displayIDs = []
    }
    
    func configureDisplays() {
        self.clearDisplays()
        var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
           return
        }
        self.displayIDs = onlineDisplayIDs
    }
    
    func setBrightness(level:Float) {
        guard let builtInDisplayID = builtInDisplayID else {
            return
        }

        DisplayServicesSetBrightness(builtInDisplayID, level)
    }
    
    func getBrightness() -> Float {
        guard let builtInDisplayID = builtInDisplayID else {
            return 1.0
        }
        var brightness: Float = 0
        DisplayServicesGetBrightness(builtInDisplayID, &brightness)
        return brightness
    }
    
    private func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
        var brightness: Float = -1
        let ret = DisplayServicesGetBrightness(displayID, &brightness)
        if ret == 0, brightness >= 0 { // If brightness read appears to be successful using DisplayServices then it should be an Apple display
            return true
        }
        if CGDisplayIsBuiltin(displayID) != 0 { // If built-in display then it should be Apple (except for hackintosh notebooks...)
            return true
        }
        return false
    }
}
