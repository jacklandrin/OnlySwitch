//
//  EmptyTrashSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import Switches
import Defines

final class EmptyTrashSwitch:SwitchProvider {

    var type: SwitchType = .emptyTrash
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func currentStatus() async -> Bool {
        return true
    }

    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await emptyTrashCMD.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }
}
