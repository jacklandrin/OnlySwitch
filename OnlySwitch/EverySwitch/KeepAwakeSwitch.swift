//
//  KeepAwakeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/13.
//

import AppKit
import IOKit
import IOKit.pwr_mgt

let KeepAwakeKey = "KeepAwakeKey"

class KeepAwakeSwitch:SwitchProvider {
//    static let shared = KeepAwakeSwitch()
    var type: SwitchType = .keepAwake
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .keepAwake)
    var barInfo: SwitchBarInfo = SwitchBarInfo(title: "Keep Awake".localized(),
                                               onImage: NSImage(systemSymbolName: "lock.slash.fill"),
                                               offImage: NSImage(systemSymbolName: "lock.slash"))
    private let reasonForActivity = "Reason for activity" as CFString
    private var assertionID: IOPMAssertionID = IOPMAssertionID()
    private var preventedSleep = false
    
    init() {
        switchBarVM.switchOperator = self
        let iskeepingAwake = UserDefaults.standard.bool(forKey: KeepAwakeKey)
        if iskeepingAwake {
           let success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                        reasonForActivity,
                                                        &assertionID )
            if success == kIOReturnSuccess {
                self.preventedSleep = true
            } else {
                self.preventedSleep = false
            }
        }
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return preventedSleep
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            let success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                        reasonForActivity,
                                                        &assertionID )
            if success == kIOReturnSuccess {
                preventedSleep = true
                UserDefaults.standard.set(preventedSleep, forKey: KeepAwakeKey)
                UserDefaults.standard.synchronize()
                return true
            }
            return false
        } else {
            let success = IOPMAssertionRelease(assertionID)
            if success == kIOReturnSuccess {
                preventedSleep = false
                UserDefaults.standard.set(preventedSleep, forKey: KeepAwakeKey)
                UserDefaults.standard.synchronize()
                return true
            }
            return false
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
}
