//
//  ShortcutsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation
import KeyboardShortcuts

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
    
    @Published var keyboardShortcutName:KeyboardShortcuts.Name
    
    init(name:String, toggle:Bool, error: @escaping (_ info:String) -> Void) {
        self.name = name
        self.toggle = toggle
        self.error = error
        self.keyboardShortcutName = KeyboardShortcuts.Name(rawValue: name)!
    }
    
    func doShortcuts() {
        let _ = runShortcut(name: self.name).runAppleScript(isShellCMD: true).0
    }
    
}

class ShortcutsSettingVM:ObservableObject {
    static let shared = ShortcutsSettingVM()
    @Published var shortcutsList : [ShorcutsItem] = [ShorcutsItem]()
    @Published var errorInfo = ""
    @Published var showErrorToast = false
    func loadShortcutsList() {
        DispatchQueue.main.async {
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
        
    }
    
    func addItem(name:String, toggle:Bool) {
        self.shortcutsList.append(ShorcutsItem(name: String(name), toggle: toggle, error: {[weak self] info in
            guard let strongSelf = self else {return}
            strongSelf.errorInfo = info
            strongSelf.showErrorToast = true
        }))
    }
    
    func getAllInstalledShortcutName() -> [String]? {
        let result = getShortcutsList.runAppleScript(isShellCMD: true)
        if result.0 {
            let allshortcuts = (result.1 as! String).split(separator: "\r")
            return allshortcuts.map{String($0)}
        }
        return nil
    }
    
    //TODO: read from json
    @Published var sharedShortcutsList:[SharedShortcutsItem] = [SharedShortcutsItem(name: "Toggle Scroll Direction",
                                                                                    link: "https://www.icloud.com/shortcuts/8d65c606d1924f098b22774de6dc08f8"),
                                                                SharedShortcutsItem(name: "DarkMode Switch",
                                                                                    link: "https://www.icloud.com/shortcuts/0a9a3cbbb84d4d7fa515909edef60556")]
    func checkIfInstalled() {
        let installedShortcuts = getAllInstalledShortcutName()
        guard let installedShortcuts = installedShortcuts else {
            return
        }

        for item in sharedShortcutsList {
            if installedShortcuts.contains(item.name) {
                item.hasInstalled = true
            }
        }
        objectWillChange.send()
    }
    
}

class SharedShortcutsItem:ObservableObject {
    let name:String
    let link:String
    @Published var hasInstalled = false
    init(name:String, link:String) {
        self.name = name
        self.link = link
    }
}

