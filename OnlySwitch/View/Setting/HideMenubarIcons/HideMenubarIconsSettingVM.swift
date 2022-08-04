//
//  HideMenubarIconsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation
import SwiftUI
import Combine

class HideMenubarIconsSettingVM:ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var preferencesPublisher = PreferencesPublisher.shared
    private var preferences = PreferencesPublisher.shared.preferences
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
    
    
    init() {
        preferencesPublisher.$preferences.sink{_ in
            self.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    func converTimeDescription(duration:Int) -> String {
        if duration == 0 {
            return "never".localized()
        } else if duration == 60 {
            return "1 minute".localized()
        } else {
            return "\(duration) " + "seconds".localized()
        }
    }
}

