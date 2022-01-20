//
//  EmptyPasteboardSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import AppKit
class EmptyPasteboardSwitch:SwitchProvider {
    var type: SwitchType = .emptyPasteboard
    
    func currentStatus() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString("", forType: .string)
        }
        return true
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
    
    
}
