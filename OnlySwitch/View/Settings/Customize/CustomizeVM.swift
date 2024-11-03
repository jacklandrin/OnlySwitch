//
//  CustomizeVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import KeyboardShortcuts
import Switches

@MainActor
class CustomizeVM:ObservableObject {
    static let shared  = CustomizeVM()
    @Published var allSwitches:[CustomizeItem] = [CustomizeItem]()
    @Published var errorInfo = ""
    @Published var showErrorToast = false
    init() {
        let state = SwitchManager.shared.getAllSwitchState()
        for index in 0..<switchTypeCount {
            let bitwise:UInt64 = 1 << index
            let toggle = (state & bitwise == 0) ? false : true
            allSwitches.append(CustomizeItem(type: SwitchType(rawValue: bitwise)!, toggle: toggle, error: { [weak self] info in
                guard let strongSelf = self else {return}
                strongSelf.errorInfo = info
                strongSelf.showErrorToast = true
            }))
        }
    }
}

@MainActor
class CustomizeItem: ObservableObject {
    let type:SwitchType
    let error:(_ info:String) -> Void
    @Published var toggle:Bool
    {
        didSet {
            if toggle {
                if type == .radioStation {
                    SwitchManager.shared.register(aswitch: RadioStationSwitch.shared)
                } else {
                    SwitchManager.shared.register(aswitch: type.getNewSwitchInstance())
                }
                
            } else {
                if SwitchManager.shared.shownSwitchCount < 5 {
                    error("At least remain 4 switches")
                    toggle = true
                    return
                }
                if type == .radioStation {
                    RadioStationSwitch.shared.playerItem.isPlaying = false
                }
                SwitchManager.shared.unregister(for: type)
            }
            
            let state = SwitchManager.shared.getAllSwitchState()
            let newState:UInt64 = type.rawValue ^ state
            let newStateStr = String(newState)
            UserDefaults.standard.set(newStateStr, forKey: UserDefaults.Key.SwitchState)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var keyboardShortcutName:KeyboardShortcuts.Name
    
    init(type:SwitchType, toggle:Bool, error:@escaping (_ info:String) -> Void) {
        self.type = type
        self.toggle = toggle
        self.error = error
        self.keyboardShortcutName = KeyboardShortcuts.Name(rawValue: String(type.rawValue))!
    }
    
    func doSwitch() {
        type.doSwitch()
    }
}
