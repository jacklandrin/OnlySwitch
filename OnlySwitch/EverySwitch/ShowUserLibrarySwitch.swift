//
//  ShowUserLibrarySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/20.
//

import Foundation
import Switches
import Defines

final class ShowUserLibrarySwitch: SwitchProvider {
    var type: SwitchType = .showUserLibrary
    weak var delegate: SwitchDelegate?
    private let manager = FileManager.default

    private var userLibaray : URL?

    init() {
        self.userLibaray = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    }

    @MainActor
    func currentStatus() async -> Bool {
        guard let userLibaray else {
            return false
        }

        return !userLibaray.isHidden
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
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
