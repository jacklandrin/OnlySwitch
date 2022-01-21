//
//  ShortcutsBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import Foundation

class ShortcutsBarVM:BarProvider,ObservableObject {
    
    @Published var name:String
    @Published var processing:Bool = false
    @Published var isHidden: Bool = false
    @Published var weight: Int = 0
    
    var barName: String {
        name
    }
    
    init(name:String) {
        self.name = name
    }
    
    func runShortCut() {
        processing = true
        Task{
            let _ = await operateCMD()
            DispatchQueue.main.async {
                self.processing = false
            }
        }
    }
    
    func operateCMD() async -> Bool {
        ShorcutsCMD.runShortcut(name: self.name).runAppleScript(isShellCMD: true).0
    }
}
