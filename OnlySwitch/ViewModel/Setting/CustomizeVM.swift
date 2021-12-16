//
//  CustomizeVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation


class CustomizeVM:ObservableObject {
    @Published var allSwitches:[CustomizeItem] = [CustomizeItem]()
    
    init() {
        let state = SwitchManager.shared.getAllSwitchState()
        for index in 0..<switchTypeCount {
            let bitwise:UInt64 = 1 << index
            let toggle = (state & bitwise == 0) ? false : true
            allSwitches.append(CustomizeItem(type: SwitchType(rawValue: bitwise)!, toggle: toggle))
        }
    }
}

class CustomizeItem:ObservableObject {
    
    let type:SwitchType
    @Published var toggle:Bool
    {
        didSet {
            if toggle {
                SwitchManager.shared.register(aswitch: type.getNewSwitchInstance())

            } else {
                if type == .radioStation {
                    RadioStationSwitch.shared.playerItem.isPlaying = false
                }
                SwitchManager.shared.unregister(for: type)
            }
            let state = SwitchManager.shared.getAllSwitchState()
            let newState:UInt64 = type.rawValue ^ state
            let newStateStr = String(newState)
            UserDefaults.standard.set(newStateStr, forKey: SwitchStateKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    init(type:SwitchType, toggle:Bool) {
        self.type = type
        self.toggle = toggle
    }
    
    
}
