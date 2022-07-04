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
    
    func operationSwitch(isOn: Bool) async throws {
        DispatchQueue.main.async {
            if isOn {
                self.view = NSHostingView(rootView: PureColorView())
                self.view?.enterFullScreenMode(self.getScreenWithMouse()!)
            } else {
                self.view?.exitFullScreenMode()
                self.view = nil
            }
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
