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
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString("", forType: .string)
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    
    
    
}
