//
//  PomodoroTimerSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation
import Switches

class PomodoroTimerSwitch: SwitchProvider {
    static let shared = PomodoroTimerSwitch()
    weak var delegate: SwitchDelegate?
    enum Status:String {
        case none = "n"
        case work = "w"
        case rest = "r"
    }
    
    private var restTimer:Timer?
    private var workTimer:Timer?
    var type: SwitchType = .pomodoroTimer
    
    var nextDate:Date?
    
    var status:Status = .none
    
    private var restDuration:Int {
        Preferences.shared.restDuration
    }

    private var workDuration:Int {
        Preferences.shared.workDuration
    }
    // for test
//    private var restDuration:Int = 5
//    private var workDuration:Int = 10
    
    private var restAlert:String {
        Preferences.shared.restAlert
    }

    private var workAlert:String {
        Preferences.shared.workAlert
    }
    
    private var allowNotificationAlert:Bool {
        Preferences.shared.allowNotificationAlert
    }
    
    private var cycleCount:Int {
        Preferences.shared.cycleCount
    }
    
    private var cycleIndex:Int = 0
    
    private var isRestTimerValid:Bool {
        guard let restTimer = restTimer else {
            return false
        }
        
        return restTimer.isValid
    }
    
    private var isWorkTimerValid:Bool {
        guard let workTimer = workTimer else {
            return false
        }
        return workTimer.isValid
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: .changePTDuration, object: nil, queue: .main) { _ in
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
    
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            self.cycleIndex = 0
            self.startTimer()
        } else {
            self.stopTimer()
        }
    }
    
    func isVisible() -> Bool {
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
                    let _ = try? displayNotificationCMD(title: "Take a break!".localized(),
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
                    let _ = try? displayNotificationCMD(title: "Get on with work!".localized(),
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
                        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.pomodoroTimer)
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

