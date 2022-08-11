//
//  BackNoisesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation

class BackNoisesSwitch:SwitchProvider {
    
    var type: SwitchType = .backNoises
    
    var delegate: SwitchDelegate?
    
    let backNoisesTrackManager = BackNoisesTrackManager.shared
    
    func currentStatus() -> Bool {
        backNoisesTrackManager.currentBackNoisesItem.isPlaying
    }
    
    func currentInfo() -> String {
        backNoisesTrackManager.currentBackNoisesItem.title
    }
    
    func operationSwitch(isOn: Bool) async throws {
        DispatchQueue.main.async {
            self.backNoisesTrackManager.currentBackNoisesItem.isPlaying = isOn
        }
    }
    
    func isVisable() -> Bool {
        return Preferences.shared.radioEnable
    }

}

