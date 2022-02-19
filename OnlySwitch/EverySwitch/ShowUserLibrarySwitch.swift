//
//  ShowUserLibrarySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/20.
//

import Foundation

class ShowUserLibrarySwitch:SwitchProvider {
    var type: SwitchType = .showUserLibrary
    var delegate: SwitchDelegate?
    private let manager = FileManager.default
    
    private var userLibaray : URL?
    
    init() {
        self.userLibaray = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    }
    
    func currentStatus() -> Bool {
        guard let userLibaray = userLibaray else {
            return false
        }

        return !userLibaray.isHidden
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        return userLibaray?.doHide(!isOn) ?? false
    }
    
    func isVisable() -> Bool {
        return true
    }
}
