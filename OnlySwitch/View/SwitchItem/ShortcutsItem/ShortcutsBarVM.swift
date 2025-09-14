//
//  ShortcutsBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import Foundation
import Switches

class ShortcutsBarVM: BarProvider, ObservableObject {
    
    @Published private var model = ShortcutsBarModel()
    
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
