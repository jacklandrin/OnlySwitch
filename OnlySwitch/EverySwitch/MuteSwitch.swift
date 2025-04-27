//
//  MuteSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Foundation
import AppKit
import Switches
import Defines

final class MuteSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .mute
    private let muteSwitchOperator:MuteSwitchProtocal = NSMuteSwitchOperator()
    private let pollingInterval: DispatchTimeInterval = .seconds(1)
    private let pollingQueue = DispatchQueue.main
    private var isSuspendQueue = true
    private var isMute:Bool = false {
        willSet {
            if isMute != newValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.mute)
                }
            }
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(
            forName: .showPopover,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                guard let self else {return}
                self.isSuspendQueue = false
                self.startVolumePoll()
            }
        )

        NotificationCenter.default.addObserver(
            forName: .hidePopover,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                guard let self else {return}
                self.pollingQueue.suspend()
                self.isSuspendQueue = true
            }
        )
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        try await muteSwitchOperator.operationSwitch(isOn: isOn)
    }

    @MainActor
    func currentStatus() async -> Bool {
        return await muteSwitchOperator.currentStatus()
    }
    
    func isVisible() -> Bool {
        return true
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }
    
    private func scheduleNextPoll(on queue: DispatchQueue) {
        queue.asyncAfter(deadline: .now() + pollingInterval) {
            Task {
                self.isMute = await self.muteSwitchOperator.currentStatus()
                if !self.isSuspendQueue {
                    self.scheduleNextPoll(on: queue)
                }
            }
        }
    }
    
    private func startVolumePoll() {
        scheduleNextPoll(on: pollingQueue)
    }

}

protocol MuteSwitchProtocal {
    func currentStatus() async -> Bool
    func operationSwitch(isOn: Bool) async throws
}

class NSMuteSwitchOperator: MuteSwitchProtocal {
    func currentStatus() async -> Bool {
        if NSSound.systemVolumeIsMuted {
            return true
        } else {
            let volume = NSSound.systemVolume
            UserDefaults.standard.set(volume, forKey: UserDefaults.Key.NSVolume)
            UserDefaults.standard.synchronize()
            return false
        }
    }
    
    func operationSwitch(isOn: Bool) async throws {
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

class ASMuteSwitchOperator: MuteSwitchProtocal {
    func currentStatus() async -> Bool {
        do {
            let result = try await VolumeCMD.getOutput.runAppleScript()

            let volume:String = result
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: UserDefaults.Key.ASVolume)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
            
        } catch {
            return false
        }
        
    }
    
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                let cmd = VolumeCMD.setOutput + "0"
                _ = try await cmd.runAppleScript()
            } else {
                var volumeValue = UserDefaults.standard.integer(forKey: UserDefaults.Key.ASVolume)
                volumeValue = (volumeValue == 0) ? 50 : volumeValue
                let cmd = VolumeCMD.setOutput + String(volumeValue)
                _ = try await cmd.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
