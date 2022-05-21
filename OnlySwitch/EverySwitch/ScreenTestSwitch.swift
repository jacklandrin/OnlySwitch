//
//  ScreenCheck.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import Foundation

class ScreenTestSwitch:SwitchProvider {
    var type: SwitchType = .screenTest
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return Router.isShown(windowController: Router.pureColorWindowController)
        
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        DispatchQueue.main.async {
            if isOn {
                OpenWindows.PureColor.open()
            } else {
                Router.closeWindow(controller: Router.pureColorWindowController)
            }
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
