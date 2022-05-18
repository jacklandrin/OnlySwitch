//
//  MuteMicSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/7.
//

import Foundation

let MicVolumeKey = "MicVolumeKey"
class MuteMicSwitch:SwitchProvider {
    var type: SwitchType = .muteMicrophone
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        do {
            let volume = try VolumeCMD.getInput.runAppleScript()
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: MicVolumeKey)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
        } catch {
            return false
        }
        
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                let cmd = VolumeCMD.setInput + "0"
                _ = try cmd.runAppleScript()
            } else {
                var volumeValue = UserDefaults.standard.integer(forKey: MicVolumeKey)
                volumeValue = (volumeValue == 0) ? 50 : volumeValue
                let cmd = VolumeCMD.setInput + String(volumeValue)
                _ = try cmd.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
