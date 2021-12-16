//
//  SwitchManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Foundation
import AppKit

let SwitchStateKey = "SwitchStateKey"
class SwitchManager {
    static let shared = SwitchManager()
    
    private var shownSwitchMap = [SwitchType: SwitchProvider?]()
    
    func register(aswitch:SwitchProvider) {
        shownSwitchMap[aswitch.type] = aswitch
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
    }
    
    func unregister(for type:SwitchType) {
        shownSwitchMap.removeValue(forKey: type)
        shownSwitchMap[type]? = nil
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
    }
    
    func getSwitch(of type:SwitchType) -> SwitchProvider? {
        return shownSwitchMap[type] ?? nil
    }
    
    func barVMList() -> [SwitchBarVM] {
        let sortedSwitchMap = shownSwitchMap.sorted() {$0.key.rawValue < $1.key.rawValue}
        var switchBarVMs = [SwitchBarVM]()
        for (_, value) in sortedSwitchMap {
            if let aswitch = value {
                switchBarVMs.append(aswitch.switchBarVM)
            }
        }
        return switchBarVMs
    }
    
    func registerSwitchesShouldShow() {
        let state = getAllSwitchState()
        for index in 0..<switchTypeCount {
            let bitwise:UInt64 = 1 << index
            let shouldShow = (state & bitwise == 0) ? false : true
            if shouldShow {
                self.register(aswitch: SwitchType(rawValue: bitwise)!.getNewSwitchInstance())
            }
        }
    }
    
    func getAllSwitchState() -> UInt64 {
        if let stateStr = UserDefaults.standard.string(forKey: SwitchStateKey) {
            let state = UInt64(stateStr) ?? 16383 // binary 11111111111111
            return state
        } else {
            return 16383
        }
    }
}
