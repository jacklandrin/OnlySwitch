//
//  HideMenubarIconsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

class HideMenubarIconsSwitch:SwitchProvider {
    var type: SwitchType = .hideMenubarIcons
    
    var delegate: SwitchDelegate?
    
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    private var isMenubarCollapse:Bool {
        didSet {
            NotificationCenter.default.post(name: .toggleMenubarCollapse, object: isMenubarCollapse)
        }
    }
    
    func currentStatus() -> Bool {
        return isMenubarCollapse
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        isMenubarCollapse = isOn
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
