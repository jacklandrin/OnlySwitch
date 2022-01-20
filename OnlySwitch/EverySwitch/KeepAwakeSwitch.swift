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
    static let shared = KeepAwakeSwitch()
    var type: SwitchType = .keepAwake
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .keepAwake)
    
    private let reasonForActivity = "Reason for activity" as CFString
    private var assertionID: IOPMAssertionID = IOPMAssertionID()
    @UserDefaultValue(key: KeepAwakeKey, defaultValue: false)
    private var preventedSleep
    
    init() {
        switchBarVM.switchOperator = self
        if preventedSleep {
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
                return true
            }
            return false
        } else {
            let success = IOPMAssertionRelease(assertionID)
            if success == kIOReturnSuccess {
                preventedSleep = false
                return true
            }
            return false
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
}
