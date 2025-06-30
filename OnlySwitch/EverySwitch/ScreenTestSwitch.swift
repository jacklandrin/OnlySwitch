//
//  ScreenCheck.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import Foundation
import AppKit
import SwiftUI
import Switches

final class ScreenTestSwitch: SwitchProvider, CurrentScreen {

    static let shared = ScreenTestSwitch()
    
    var type: SwitchType = .screenTest
    
    var delegate: SwitchDelegate?
    
    var view:NSView?

    @MainActor
    func currentStatus() async -> Bool {
        return view != nil
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        guard self.checkAccessbilityEnabled() else { return }
        if isOn {
            self.view = NSHostingView(rootView: PureColorView())
            self.view?.enterFullScreenMode(self.getScreenWithMouse()!)
        } else {
            self.view?.exitFullScreenMode()
            self.view = nil
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    private func checkAccessbilityEnabled() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
