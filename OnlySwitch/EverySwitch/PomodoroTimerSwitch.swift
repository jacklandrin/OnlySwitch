//
//  PomodoroTimerSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation
import Switches

final class PomodoroTimerSwitch: SwitchProvider {
    static let shared = PomodoroTimerSwitch()
    weak var delegate: SwitchDelegate?
    enum Status:String {
        case none = "n"
        case work = "w"
        case rest = "r"
    }
    
    private var restTimer: Timer?
    private var workTimer: Timer?
    var type: SwitchType = .pomodoroTimer
    
    var nextDate: Date?

    var status: Status = .none

    private var restDuration: Int {
        Preferences.shared.restDuration
    }

    private var workDuration: Int {
        Preferences.shared.workDuration
    }
    // for test
//    private var restDuration:Int = 5
//    private var workDuration:Int = 10
    
    private var restAlert: String {
        Preferences.shared.restAlert
    }

    private var workAlert: String {
        Preferences.shared.workAlert
    }
    
    private var allowNotificationAlert: Bool {
        Preferences.shared.allowNotificationAlert
    }
    
    private var cycleCount: Int {
        Preferences.shared.cycleCount
    }
    
    private var cycleIndex: Int = 0
    
    private var isRestTimerValid: Bool {
        guard let restTimer = restTimer else {
            return false
        }
        
        return restTimer.isValid
    }
    
    private var isWorkTimerValid: Bool {
        guard let workTimer = workTimer else {
            return false
        }
        return workTimer.isValid
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: .changePTDuration, object: nil, queue: .main) { _ in
            Task { @MainActor in
               await self.stopTimer()
            }
        }
    }

    @MainActor
    func currentStatus() async -> Bool {
        return self.status != .none //isRestTimerValid && isWorkTimerValid
    }

    @MainActor
    func currentInfo() async -> String {
        guard let nextDate else {
            status = .none
            return ""
        }
        
        let leftSecond = Int(nextDate.timeIntervalSinceNow)
        if leftSecond >= 0 {
            return String(format: "%@-%02d:%02d", status.rawValue, leftSecond / 60, leftSecond % 60)
        } else {
            status = .none
            return ""
        }
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            self.cycleIndex = 0
            self.startTimer()
        } else {
            await self.stopTimer()
        }
    }
    
    func isVisible() -> Bool {
        return true
    }

    func startTimer() {
        nextDate = .now + TimeInterval(workDuration + 1)
        status = .work

        self.restTimer = Timer(timeInterval: TimeInterval(self.workDuration + 1), repeats: false) { [weak self] timer in
            guard let self else { return }
            Task { @MainActor in
                self.restTimer?.invalidate()
                self.restTimer = nil
                EffectSoundHelper.shared.playSound(name: self.restAlert, type: "wav")
                if self.allowNotificationAlert {
                    let _ = try? await displayNotificationCMD(title: "Take a break!".localized(),
                                                              content: "You've worked for %d min."
                        .localizeWithFormat(arguments: self.workDuration / 60),
                                                              subtitle: "Time's up.".localized())
                        .runAppleScript()

                }
                self.nextDate = .now + TimeInterval(self.restDuration + 1)
                self.status = .rest
            }
        }

        self.workTimer = Timer(timeInterval: TimeInterval(self.workDuration + self.restDuration + 1), repeats: false) { [weak self] timer in
            guard let self else { return }
            Task { @MainActor in
                self.workTimer?.invalidate()
                self.workTimer = nil
                EffectSoundHelper.shared.playSound(name: self.workAlert, type: "wav")
                if self.allowNotificationAlert {
                    let _ = try? await displayNotificationCMD(title: "Get on with work!".localized(),
                                                              content: "You've rested for %d min."
                        .localizeWithFormat(arguments: self.restDuration / 60),
                                                              subtitle: "Time's up.".localized())
                        .runAppleScript()
                }

                self.cycleIndex += 1
                if self.cycleCount == 0 || self.cycleIndex < self.cycleCount {
                    if self.status != .none {
                        self.startTimer()
                    }
                } else {
                    self.status = .none
                    NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.pomodoroTimer)
                }
            }
        }
        
        // Add both timers to the run loop
        if let restTimer = self.restTimer {
            RunLoop.current.add(restTimer, forMode: .common)
        }
        if let workTimer = self.workTimer {
            RunLoop.current.add(workTimer, forMode: .common)
        }
    }

    @MainActor
    func stopTimer() async {
        self.restTimer?.invalidate()
        self.restTimer = nil
        self.workTimer?.invalidate()
        self.workTimer = nil
        self.nextDate = nil
        self.status = .none
    }
}

