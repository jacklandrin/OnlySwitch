//
//  ShortcutsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import AppKit
import Foundation
import KeyboardShortcuts
import Switches
import OSLog
import Extensions

class ShortcutsItem: ObservableObject {
    let error:(_ info:String) -> Void
    @Published var name:String
    @Published var toggle:Bool
    {
        didSet {
            let shortcutsDic = Preferences.shared.shortcutsDic
            guard let shortcutsDic = shortcutsDic else {
                return
            }
            if toggle {
                let showShortcutsCount = shortcutsDic.filter{$0.value == true}.count
                if showShortcutsCount > 9 {
                    error("The maximum number of shortcuts is 10")
                    toggle = false
                    return
                }
            }
            
            var newShortcutsDic = shortcutsDic
            newShortcutsDic[name] = toggle
            Preferences.shared.shortcutsDic = newShortcutsDic
            NotificationCenter.default.post(name: .changeSettings, object: nil)
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
        let shortcutName = self.name
        Task {
            _ = try? await ShorcutsCMD.runShortcut(name: shortcutName).runAppleScript(isShellCMD: true)
        }
    }
    
}

final class ShortcutsSettingVM:ObservableObject, @unchecked Sendable {
    static let shared = ShortcutsSettingVM()
    
    var shortcutsList:[ShortcutsItem] {
        get {
            return model.shortcutsList
        }
        set {
            model.shortcutsList = newValue
        }
    }
    
    var errorInfo:String {
        return model.errorInfo
    }
    
    var showErrorToast: Bool {
        get {
            return model.showErrorToast
        }
        set {
            model.showErrorToast = newValue
        }
    }
    
    @Published private var model = ShortcutsSettingModel()
    
    init() {
        shouldLoadShortcutsList()
    }
    
    func shouldLoadShortcutsList() {
        DispatchQueue.global().async {
            self.loadShortcutsList()
        }
    }
    
    private func loadShortcutsList() {
        Task { @MainActor in
            var result: String = ""
            do {
                result = try await ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
            } catch {

            }
            let allshortcuts = result.split(separator: "\r")
            let shortcutsDic = Preferences.shared.shortcutsDic
            var newShortcutsDic:[String:Bool] = [String:Bool]()
            if let shortcutsDic = shortcutsDic {
                self.model.shortcutsList = [ShortcutsItem]()
                for name in allshortcuts {
                    if let toggle = shortcutsDic[String(name)] {
                        self.addItem(name: String(name), toggle: toggle)
                        newShortcutsDic[String(name)] = toggle
                    } else {
                        self.addItem(name: String(name), toggle: false)
                        newShortcutsDic[String(name)] = false
                    }
                }
            } else {
                self.model.shortcutsList = allshortcuts.map{ ShortcutsItem(name: String($0), toggle: false, error: {[weak self] info in
                    guard let strongSelf = self else {return}
                    strongSelf.model.errorInfo = info
                    strongSelf.model.showErrorToast = true
                }) }
                for name in allshortcuts {
                    newShortcutsDic[String(name)] = false
                }
            }

            Preferences.shared.shortcutsDic = newShortcutsDic
            refreshShortcutAppearances(for: newShortcutsDic.compactMap { $0.value ? $0.key : nil })
        }
    }

    private func refreshShortcutAppearances(for names: [String]) {
        Task { @MainActor in await ShortcutAppearanceLoader.refresh(for: names) }
    }

    func addItem(name: String, toggle: Bool) {
        self.model.shortcutsList.append(ShortcutsItem(name: String(name), toggle: toggle, error: {[weak self] info in
            guard let strongSelf = self else {return}
            strongSelf.model.errorInfo = info
            strongSelf.model.showErrorToast = true
        }))
    }
    
    func getAllInstalledShortcutName() async -> [String]? {
        do {
            let result = try await ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
            let allshortcuts = result.split(separator: "\r")
            return allshortcuts.map{String($0)}
        } catch {
            return nil
        }
        
    }
}
