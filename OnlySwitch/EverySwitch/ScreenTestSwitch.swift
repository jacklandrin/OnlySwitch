//
//  ScreenCheck.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import Foundation
import AppKit
import SwiftUI

class ScreenTestSwitch:SwitchProvider, CurrentScreen {
    
    static let shared = ScreenTestSwitch()
    
    var type: SwitchType = .screenTest
    
    var delegate: SwitchDelegate?
    
    var view:NSView?
    
    func currentStatus() -> Bool {
        return view != nil
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        DispatchQueue.main.async {
            guard self.checkAccessbilityEnabled() else { return }
            if isOn {
                self.view = NSHostingView(rootView: PureColorView())
                self.view?.enterFullScreenMode(self.getScreenWithMouse()!)
            } else {
                self.view?.exitFullScreenMode()
                self.view = nil
            }
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
