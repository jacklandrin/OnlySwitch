//
//  MuteSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Foundation
import AppKit


class MuteSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .mute
    private let muteSwitchOperator:MuteSwitchProtocal = NSMuteSwitchOperator()
    private let pollingInterval: DispatchTimeInterval = .seconds(1)
    private let pollingQueue = DispatchQueue.main
    private var isSuspendQueue = true
    private var isMute:Bool = false {
        willSet {
//            print("isMute:\(newValue)")
            if isMute != newValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.mute)
                }
            }
        }
    }
    
    init() {
//        print("mute init")
        NotificationCenter.default.addObserver(forName: .showPopover, object: nil, queue: .main, using: { [weak self] _ in
            guard let StrongSelf = self else {return}
            StrongSelf.isSuspendQueue = false
            StrongSelf.startVolumePoll()
        })
        
        NotificationCenter.default.addObserver(forName: .hidePopover, object: nil, queue: .main, using: {[weak self] _ in
            guard let StrongSelf = self else {return}
            StrongSelf.pollingQueue.suspend()
            StrongSelf.isSuspendQueue = true
        })
    }
    
    deinit{
//        print("mute deinit")
    }
    
    func operationSwitch(isOn: Bool) async throws {
        try muteSwitchOperator.operationSwitch(isOn: isOn)
    }
    
    func currentStatus() -> Bool {
        return muteSwitchOperator.currentStatus()
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    private func scheduleNextPoll(on queue: DispatchQueue) {
        queue.asyncAfter(deadline: .now() + pollingInterval) {
            self.isMute = self.muteSwitchOperator.currentStatus()
            if !self.isSuspendQueue {
                self.scheduleNextPoll(on: queue)
            }
        }
    }
    
    private func startVolumePoll() {
        scheduleNextPoll(on: pollingQueue)
    }

}

protocol MuteSwitchProtocal {
    func currentStatus() -> Bool
    func operationSwitch(isOn: Bool) throws
}

class NSMuteSwitchOperator:MuteSwitchProtocal {
    func currentStatus() -> Bool {
        if NSSound.systemVolumeIsMuted {
            return true
        } else {
            let volume = NSSound.systemVolume
            UserDefaults.standard.set(volume, forKey: UserDefaults.Key.NSVolume)
            UserDefaults.standard.synchronize()
            return false
        }
    }
    
    func operationSwitch(isOn: Bool) throws {
        
        if isOn {
            NSSound.systemVolumeFadeToMute(seconds: 0, blocking: true)
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn on, isMuted:\(isMuted)")
            if !isMuted {
                throw SwitchError.OperationFailed
            }
        } else {
            var volumeValue = Float(UserDefaults.standard.float(forKey: UserDefaults.Key.NSVolume))
            if volumeValue == 0 {
                volumeValue = 0.5
            }
            NSSound.systemVolume = volumeValue
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn off, isMuted:\(isMuted)")
            if isMuted {
                throw SwitchError.OperationFailed
            }
        }
    }
}

class ASMuteSwitchOperator:MuteSwitchProtocal {
    func currentStatus() -> Bool {
        do {
            let result = try VolumeCMD.getOutput.runAppleScript()
            
            let volume:String = result
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: UserDefaults.Key.ASVolume)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
            
        } catch {
            return false
        }
        
    }
    
    func operationSwitch(isOn: Bool) throws {
        do {
            if isOn {
                let cmd = VolumeCMD.setOutput + "0"
                _ = try cmd.runAppleScript()
            } else {
                var volumeValue = UserDefaults.standard.integer(forKey: UserDefaults.Key.ASVolume)
                volumeValue = (volumeValue == 0) ? 50 : volumeValue
                let cmd = VolumeCMD.setOutput + String(volumeValue)
                _ = try cmd.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
