//
//  ShowUserLibrarySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/20.
//

import Foundation

class ShowUserLibrarySwitch:SwitchProvider {
    var type: SwitchType = .showUserLibrary
    weak var delegate: SwitchDelegate?
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
    
    func operateSwitch(isOn: Bool) async throws {
        let result = userLibaray?.doHide(!isOn) ?? false
        if !result {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
