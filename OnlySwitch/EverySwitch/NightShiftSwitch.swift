//
//  NightShiftSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/5.
//

import AppKit
import Combine
import Switches

class NightShiftSwitch: SwitchProvider {
    static let shared = NightShiftSwitch()
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .nightShift

    private var nightshiftStrength = Preferences.shared.nightShiftStrength
    private var startDate = Preferences.shared.nightShiftStartDate
    private var endDate = Preferences.shared.nightShiftEndDate
    private var isNightShiftScheduleOn = Preferences.shared.isNightShiftScheduleOn

    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var cancellable = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.addObserver(forName: .changeNightShiftSetting, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.nightshiftStrength != Preferences.shared.nightShiftStrength {
                self.nightshiftStrength = Preferences.shared.nightShiftStrength
                if self.currentStatus() {
                    NightShiftTool.strength = nightshiftStrength
                }
            }
            self.startDate = Preferences.shared.nightShiftStartDate
            self.endDate = Preferences.shared.nightShiftEndDate
            self.isNightShiftScheduleOn = Preferences.shared.isNightShiftScheduleOn
        }
        setTimer()
    }

    func isVisible() -> Bool {
        return NightShiftTool.supportsNightShift
    }

    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return NightShiftTool.isNightShiftEnabled
    }
    
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            switchOn()
        } else {
            switchOff()
        }
    }

    private func switchOff() {
        NightShiftTool.disable()
    }

    private func switchOn() {
        NightShiftTool.enable()
        NightShiftTool.strength = nightshiftStrength
    }

    private func setTimer() {
        secondTimer.sink { [weak self] _ in
            guard let self else { return }
            if self.isNightShiftScheduleOn {
                self.scheduleTask()
            }
        }.store(in: &cancellable)
    }

    private func scheduleTask() {
        let startTimeToday = Date().date(at: 0, minutes: 0).timeIntervalSince1970 + startDate
        var endTimeToday = Date().date(at: 0, minutes: 0).timeIntervalSince1970 + endDate
        if endTimeToday <= startTimeToday {
            endTimeToday += 24 * 60 * 60 //tomorrow time
        }
        let nowTimeInterval = Date().timeIntervalSince1970
        if currentStatus() {
            if endTimeToday >= nowTimeInterval - 1 && endTimeToday <= nowTimeInterval + 1 {
                switchOff()
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
            }
        } else {
            if startTimeToday >= nowTimeInterval - 1 && startTimeToday <= nowTimeInterval + 1 {
                switchOn()
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
            }
        }
    }
}

class NightShiftTool {
    private static let client = CBBlueLightClient()

    private static var blueLightStatus: Status {
        var status: Status = Status()
        client.getBlueLightStatus(&status)
        return status
    }

    static var strength: Float {
        get {
            var strength: Float = 0
            client.getStrength(&strength)
            return strength
        }
        set {
            client.setStrength(newValue, commit: true)
        }
    }

    static func previewStrength(_ value: Float) {
        // Check if user manually disabled Night Shift
        if !isNightShiftEnabled { isNightShiftEnabled = true }
        client.setStrength(value, commit: false)
    }

    static var isNightShiftEnabled: Bool {
        get { return blueLightStatus.enabled.boolValue }
        set { client.setEnabled(newValue) }
    }

    public static func enable() {
        isNightShiftEnabled = true
    }

    public static func disable() {
        isNightShiftEnabled = false
    }

    static var supportsNightShift: Bool { return CBBlueLightClient.supportsBlueLightReduction() }
}
