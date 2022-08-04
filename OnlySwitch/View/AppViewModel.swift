//
//  AppViewModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/4.
//

import Foundation

class AppViewModel:ObservableObject {
    @Published private var preferences = Preferences.shared
    
    var radioPlayEnable:Bool {
        get {
            preferences.radioEnable
        }
        
        set {
            preferences.radioEnable = newValue
        }
    }
    
    var hideMenubarIconsEnable:Bool {
        get {
            preferences.menubarCollaspable
        }
        set {
            preferences.menubarCollaspable = newValue
        }
    }
}
