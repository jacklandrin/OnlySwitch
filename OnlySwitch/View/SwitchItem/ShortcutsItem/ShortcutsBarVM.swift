//
//  ShortcutsBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import Foundation

class ShortcutsBarVM:BarProvider,ObservableObject {
    
//    @Published var name:String
//    @Published var processing:Bool = false
//    @Published var isHidden: Bool = false
//    @Published var weight: Int = 0
    
    @Published private var model = ShortcutsBarModel()
    
    var barName: String {
        return model.name
    }
    
    var processing:Bool {
        return model.processing
    }
    
    var isHidden:Bool {
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
    
    init(name:String) {
        self.model.name = name
    }
    
    func runShortCut() {
        self.model.processing = true
        Task{
            let _ = await operateCMD()
            DispatchQueue.main.async {
                self.model.processing = false
            }
        }
    }
    
    func operateCMD() async -> Bool {
        do {
            _ = try ShorcutsCMD.runShortcut(name: self.model.name).runAppleScript(isShellCMD: true)
            return true
        } catch {
            return false
        }
    }
}
