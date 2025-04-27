//
//  EmptyPasteboardSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import AppKit
import Switches

final class EmptyPasteboardSwitch:SwitchProvider {
    var type: SwitchType = .emptyPasteboard
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        return true
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
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
