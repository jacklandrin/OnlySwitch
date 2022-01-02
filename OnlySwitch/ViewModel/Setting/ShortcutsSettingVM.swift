//
//  ShortcutsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation

let shorcutsDicKey = "shorcutsDicKey"

class ShorcutsItem:ObservableObject {
    let error:(_ info:String) -> Void
    @Published var name:String
    @Published var toggle:Bool
    {
        didSet {
            let shortcutsDic = UserDefaults.standard.dictionary(forKey: shorcutsDicKey)
            guard let shortcutsDic = shortcutsDic else {
                return
            }
            if toggle {
                let showShortcutsCount = shortcutsDic.filter{$0.value as! Bool == true}.count
                if showShortcutsCount > 5 {
                    error("The maximum number of shortcuts is 6")
                    toggle = false
                    return
                }
            }
            
            var newShortcutsDic = shortcutsDic
            newShortcutsDic[name] = toggle
            UserDefaults.standard.set(newShortcutsDic, forKey: shorcutsDicKey)
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: changeSettingNotification, object: nil)
        }
    }
    
    init(name:String, toggle:Bool, error: @escaping (_ info:String) -> Void) {
        self.name = name
        self.toggle = toggle
        self.error = error
    }
}

class ShortcutsSettingVM:ObservableObject {
    @Published var shortcutsList : [ShorcutsItem] = [ShorcutsItem]()
    @Published var errorInfo = ""
    @Published var showErrorToast = false
    func loadShortcutsList() {
        let result = getShortcutsList.runAppleScript(isShellCMD: true)
        if result.0 {
            let allshortcuts = (result.1 as! String).split(separator: "\r")
            let shortcutsDic = UserDefaults.standard.dictionary(forKey: shorcutsDicKey)
            var newShortcutsDic:[String:Bool] = [String:Bool]()
            if let shortcutsDic = shortcutsDic {
                self.shortcutsList = [ShorcutsItem]()
                for name in allshortcuts {
                    if let toggle = shortcutsDic[String(name)] as? Bool {
                        self.addItem(name: String(name), toggle: toggle)
                        newShortcutsDic[String(name)] = toggle
                    } else {
                        self.addItem(name: String(name), toggle: false)
                        newShortcutsDic[String(name)] = false
                    }
                }
            } else {
                self.shortcutsList = allshortcuts.map{ ShorcutsItem(name: String($0), toggle: false, error: {[weak self] info in
                    guard let strongSelf = self else {return}
                    strongSelf.errorInfo = info
                    strongSelf.showErrorToast = true
                }) }
                for name in allshortcuts {
                    newShortcutsDic[String(name)] = false
                }
            }
            
            UserDefaults.standard.set(newShortcutsDic, forKey: shorcutsDicKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    func addItem(name:String, toggle:Bool) {
        self.shortcutsList.append(ShorcutsItem(name: String(name), toggle: toggle, error: {[weak self] info in
            guard let strongSelf = self else {return}
            strongSelf.errorInfo = info
            strongSelf.showErrorToast = true
        }))
    }
}
