//
//  CustomizeVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import KeyboardShortcuts

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

class CustomizeItem:ObservableObject {
    let type:SwitchType
    let error:(_ info:String) -> Void
    @Published var toggle:Bool
    {
        didSet {
            if toggle {
//                if SwitchManager.shared.shownSwitchCount > 19 {
//                    error("The maximum number of switch is 20")
//                    toggle = false
//                    return
//                }
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
        let switchOperator = type.getNewSwitchInstance()
        let controlType = type.barInfo().controlType
        if controlType == .Switch || controlType == .Player {
            let status = switchOperator.currentStatus()
            Task {
                do {
                    _ = try await switchOperator.operateSwitch(isOn: !status)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                        if controlType == .Switch {
                            _ = try? displayNotificationCMD(title: self.type.barInfo().title.localized(),
                                                            content: "",
                                                            subtitle: status ? "Turn off".localized() : "Turn on".localized())
                            .runAppleScript()
                        }
                    }
                } catch {
                    
                }
            }
        } else if controlType == .Button {
            Task {
                do {
                    _ = try await switchOperator.operateSwitch(isOn: true)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                        _ = try? displayNotificationCMD(title: self.type.barInfo().title.localized(),
                                                        content: "",
                                                        subtitle: "Running".localized())
                        .runAppleScript()
                    }
                } catch {
                    
                }
                
            }
        }
        
    }
}
