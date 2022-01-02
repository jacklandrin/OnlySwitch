//
//  ShortcutsBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import Foundation

class ShortcutsBarVM:ObservableObject {
    @Published var name:String
    @Published var processing:Bool = false
    
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
        runShortcut(name: self.name).runAppleScript(isShellCMD: true).0
    }
}
