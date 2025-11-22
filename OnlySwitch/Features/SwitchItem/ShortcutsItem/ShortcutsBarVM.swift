//
//  ShortcutsBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import Foundation
import Switches
import Sharing

class ShortcutsBarVM: BarProvider, ObservableObject {
    
    @Published private var model = ShortcutsBarModel()
    @Shared(.appStorage(UserDefaults.Key.hideMenuAfterRunning)) var hideMenuAfterRunningShared: Bool = false
    
    var barName: String {
        return model.name
    }
    
    var processing: Bool {
        return model.processing
    }
    
    var isHidden: Bool {
        return model.isHidden
    }
    
    var weight: Int {
        get {
            return model.weight
        }
        set {
            self.model.weight = newValue
        }
    }

    var id: String {
        return model.name
    }

    init(name: String) {
        self.model.name = name
    }
    
    func runShortCut() {
        self.model.processing = true
        if hideMenuAfterRunningShared {
            NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
        }
        Task{ @MainActor in
            let _ = await operateCMD()
            self.model.processing = false
        }
    }
    
    func operateCMD() async -> Bool {
        do {
            _ = try await ShorcutsCMD.runShortcut(name: self.model.name).runAppleScript(isShellCMD: true)
            return true
        } catch {
            return false
        }
    }
}
