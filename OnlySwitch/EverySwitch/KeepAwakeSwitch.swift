//
//  KeepAwakeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/13.
//

import AppKit
import IOKit
import IOKit.pwr_mgt
import Combine
import Switches
import Defines

class KeepAwakeSwitch: SwitchProvider {
    static let shared = KeepAwakeSwitch()
    var type: SwitchType = .keepAwake
    weak var delegate: SwitchDelegate?
    private let reasonForActivity = "Reason for activity" as CFString
    private var assertionID: IOPMAssertionID = IOPMAssertionID()
    
    @UserDefaultValue(key: UserDefaults.Key.KeepAwakeKey, defaultValue: false)
    private var preventedSleep
    
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var cancellable = Set<AnyCancellable>()
    
    private var afterTimeMode:Bool = Preferences
        .shared
        .autoStopKeepAwakeMode.boolValue
    private var duration:Int = Preferences
        .shared
        .autoStopKeepAwakeTime
    private var startDate:Double = Preferences
        .shared
        .autoStopKeepAwakeStartDate
    private var endDate:Double = Preferences
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
    
    deinit {
        cancellable.removeAll()
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
            strongSelf.endDate = Preferences
                .shared
                .autoStopKeepAwakeEndDate
        }
    }
    
    private func setTimer() {
        secondTimer.sink{ [weak self] _ in
            guard let strongSelf = self else {return}
            if strongSelf.afterTimeMode {
                strongSelf.stopAfterTime()
            } else {
                strongSelf.scheduleTask()
            }
        }.store(in: &cancellable)
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
        var endTimeToday = Date().date(at: 0, minutes: 0).timeIntervalSince1970 + endDate
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
    
    func operateSwitch(isOn: Bool) async throws {
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
            timerCounter = 0
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
    
    func isVisible() -> Bool {
        return true
    }
}
