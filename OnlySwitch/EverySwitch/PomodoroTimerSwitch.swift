//
//  PomodoroTimerSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation

class PomodoroTimerSwitch: SwitchProvider {
    static let shared = PomodoroTimerSwitch()
    weak var delegate: SwitchDelegate?
    enum Status:String {
        case none = "n"
        case work = "w"
        case rest = "r"
    }
    
    var restTimer:Timer?
    var workTimer:Timer?
    var type: SwitchType = .pomodoroTimer
    
    var nextDate:Date?
    
    var status:Status = .none
    
    @UserDefaultValue(key: RestDurationKey, defaultValue: 5 * 60)
    var restDuration:Int

    @UserDefaultValue(key: WorkDurationKey, defaultValue: 25 * 60)
    var workDuration:Int
    // for test
//    var restDuration:Int = 5
//    var workDuration:Int = 10
    
    @UserDefaultValue(key: RestAlertKey, defaultValue: "mixkit-alert-bells-echo-765")
    var restAlert:String
    
    @UserDefaultValue(key: WorkAlertKey, defaultValue: "mixkit-bell-notification-933")
    var workAlert:String
    
    @UserDefaultValue(key: AllowNotificationAlertKey, defaultValue: true)
    var allowNotificationAlert:Bool
    
    @UserDefaultValue(key: PTimerCycleCountKey, defaultValue: 1)
    var cycleCount:Int
    
    var cycleIndex:Int = 0
    
    var isRestTimerValid:Bool {
        guard let restTimer = restTimer else {
            return false
        }
        
        return restTimer.isValid
    }
    
    var isWorkTimerValid:Bool {
        guard let workTimer = workTimer else {
            return false
        }
        return workTimer.isValid
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: ChangePTDurationNotification, object: nil, queue: .main) { _ in
            self.stopTimer()
        }
    }
    
    func currentStatus() -> Bool {
        return self.status != .none//isRestTimerValid && isWorkTimerValid
    }
    
    func currentInfo() -> String {
        guard let nextDate = nextDate else {
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
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            self.cycleIndex = 0
            self.startTimer()
            return true
        } else {
            self.stopTimer()
            return true
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func startTimer() {
        
        nextDate = .now + TimeInterval(workDuration + 1)
        status = .work
        DispatchQueue.main.async {
            self.restTimer = Timer(timeInterval: TimeInterval(self.workDuration + 1), repeats: false) {[weak self] timer in
                guard let strongSelf = self else {return}
                strongSelf.restTimer?.invalidate()
                strongSelf.restTimer = nil
                EffectSoundHelper.shared.playSound(name: strongSelf.restAlert, type: "wav")
                if strongSelf.allowNotificationAlert {
                    let _ = displayNotificationCMD(title: "Take a break!".localized(),
                                                   content: "You've worked for %d min."
                                                    .localizeWithFormat(arguments: strongSelf.workDuration / 60),
                                                   subtitle: "Time's up.".localized())
                        .runAppleScript()
                }
                strongSelf.nextDate = .now + TimeInterval(strongSelf.restDuration + 1)
                strongSelf.status = .rest
            }
            
            self.workTimer = Timer(timeInterval: TimeInterval(self.workDuration + self.restDuration + 1), repeats: false) {[weak self] timer in
                guard let strongSelf = self else {return}
                strongSelf.workTimer?.invalidate()
                strongSelf.workTimer = nil
                EffectSoundHelper.shared.playSound(name: strongSelf.workAlert, type: "wav")
                if strongSelf.allowNotificationAlert {
                    let _ = displayNotificationCMD(title: "Get on with work!".localized(),
                                                   content: "You've rested for %d min."
                                                    .localizeWithFormat(arguments: strongSelf.restDuration / 60),
                                                   subtitle: "Time's up.".localized())
                        .runAppleScript()
                }
            
                strongSelf.cycleIndex += 1
                if strongSelf.cycleCount == 0 || strongSelf.cycleIndex < strongSelf.cycleCount {
                    if strongSelf.status != .none {
                        strongSelf.startTimer()
                    }
                } else {
                    strongSelf.status = .none
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
                    }
                }
            }
            RunLoop.current.add(self.restTimer!, forMode: .common)
            RunLoop.current.add(self.workTimer!, forMode: .common)
        }
    }
    
    func stopTimer() {
        DispatchQueue.main.async {
            self.restTimer?.invalidate()
            self.restTimer = nil
            self.workTimer?.invalidate()
            self.workTimer = nil
            self.nextDate = nil
        }
        self.status = .none
    }
}

