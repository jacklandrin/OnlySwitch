//
//  KeepAwakeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/13.
//

import AppKit
import IOKit
import IOKit.pwr_mgt

class KeepAwakeSwitch:SwitchProvider {
    static let shared = KeepAwakeSwitch()
    var type: SwitchType = .keepAwake
    weak var delegate: SwitchDelegate?
    private let reasonForActivity = "Reason for activity" as CFString
    private var assertionID: IOPMAssertionID = IOPMAssertionID()
    
    @UserDefaultValue(key: UserDefaults.Key.KeepAwakeKey, defaultValue: false)
    private var preventedSleep
    
    private var secondTimer:Timer!
    
    private var afterTimeMode:Bool = Preferences
        .shared
        .autoStopKeepAwakeMode.boolValue
    private var duration:Int = Preferences
        .shared
        .autoStopKeepAwakeTime
    private var startDate:Double = Preferences
        .shared
        .autoStopKeepAwakeStartDate
    private var endData:Double = Preferences
        .shared
        .autoStopKeepAwakeEndDate
    
    private var timerCounter = 0
    
    private var durationBySecond:Int {
        duration * 60
    }
    
    init() {
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
        
        setSettingNotification()
        setTimer()
    }
    
    private func setSettingNotification() {
        NotificationCenter.default.addObserver(forName: .changeKeepAwakeSetting, object: nil, queue: .main) { [weak self] _ in
            guard let strongSelf = self else {return}
            strongSelf.afterTimeMode = Preferences
                .shared
                .autoStopKeepAwakeMode.boolValue
            strongSelf.duration = Preferences
                .shared
                .autoStopKeepAwakeTime
            strongSelf.startDate = Preferences
                .shared
                .autoStopKeepAwakeStartDate
            strongSelf.endData = Preferences
                .shared
                .autoStopKeepAwakeEndDate
        }
    }
    
    private func setTimer() {
        secondTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let strongSelf = self else {return}
            if strongSelf.afterTimeMode {
                strongSelf.stopAfterTime()
            } else {
                strongSelf.scheduleTask()
            }
        }
        RunLoop.current.add(self.secondTimer, forMode: .common)
    }
    
    private func stopAfterTime() {
        guard preventedSleep, durationBySecond != 0 else {return} //switch is on and duration isn't never
        timerCounter += 1
        if timerCounter == durationBySecond {
            timerCounter = 0
            try? switchOff()
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
        }
    }
    
    private func scheduleTask() {
        timerCounter = 0
        let startTimeToday = Date().date(at: 0, minutes: 0).timeIntervalSince1970 + startDate
        var endTimeToday = Date().date(at: 0, minutes: 0).timeIntervalSince1970 + endData
        if endTimeToday <= startTimeToday {
            endTimeToday += 24 * 60 * 60 //tomorrow time
        }
        let nowTimeInterval = Date().timeIntervalSince1970
        if preventedSleep {
            if endTimeToday >= nowTimeInterval - 1 && endTimeToday <= nowTimeInterval + 1 {
                try? switchOff()
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
            }
        } else {
            if startTimeToday >= nowTimeInterval - 1 && startTimeToday <= nowTimeInterval + 1 {
                try? switchOn()
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
            }
        }

    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return preventedSleep
    }
    
    func operationSwitch(isOn: Bool) async throws {
        if isOn {
            try switchOn()
        } else {
            try switchOff()
        }
    }
    
    private func switchOn() throws {
        let success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                    reasonForActivity,
                                                    &assertionID )
        if success == kIOReturnSuccess {
            preventedSleep = true
        } else {
            throw SwitchError.OperationFailed
        }
    }
    
    private func switchOff() throws {
        let success = IOPMAssertionRelease(assertionID)
        if success == kIOReturnSuccess {
            preventedSleep = false
        } else {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
}
