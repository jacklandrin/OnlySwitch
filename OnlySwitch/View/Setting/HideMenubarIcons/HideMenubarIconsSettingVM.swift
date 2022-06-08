//
//  HideMenubarIconsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation
import SwiftUI
class HideMenubarIconsSettingVM:ObservableObject {
    @Published private var preferences = Preferences.shared
    var durationSet = [0, 5, 10, 15, 30, 60]
    var isEnable:Bool {
        get {
            return preferences.menubarCollaspable
        }
        set {
            preferences.menubarCollaspable = newValue
        }
    }
    
    var automaticallyHideTime:Int {
        get {
            return preferences.autoCollapseMenubarTime
        }
        set {
            preferences.autoCollapseMenubarTime = newValue
        }
    }
    
    func converTimeDescription(duration:Int) -> String {
        if duration == 0 {
            return "never".localized()
        } else if duration == 60 {
            return "1 minute"
        } else {
            return "\(duration) " + "seconds".localized()
        }
    }
}

