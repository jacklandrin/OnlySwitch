//
//  EvolutionModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Foundation
import Switches

struct EvolutionItem: Equatable, Identifiable {
    /// Operations that an Evolution is permitted to request from the privileged
    /// helper. This allowlist is deliberately compiled into the app rather than
    /// derived from a gallery response or a persisted command.
    private static let curatedPrivilegedOperations: [UUID: PrivilegedOperation] = [
        UUID(uuidString: "0AD2A1A8-E0BA-4F6A-9E28-2E2B06143C8D")!: .clamshellSleepDisabled
    ]

    var id = UUID()
    var name = ""
    var active = false
    var iconName: String?
    var controlType: ControlType = .Switch
    var onCommand: EvolutionCommand?
    var offCommand: EvolutionCommand?
    var singleCommand: EvolutionCommand?
    var statusCommand: EvolutionCommand?
    /// Present only for a small, catalogue-curated operation.  User-authored
    /// Evolution commands never populate this value.
    var privilegedOperation: PrivilegedOperation?

    /// Returns an operation only when both its stable, shipped Evolution ID and
    /// its requested operation match the compiled allowlist. Call this at every
    /// trust boundary; `privilegedOperation` itself may originate in Core Data.
    static func trustedPrivilegedOperation(
        id: UUID,
        controlType: ControlType,
        requestedOperation: PrivilegedOperation?
    ) -> PrivilegedOperation? {
        guard let expectedOperation = curatedPrivilegedOperation(
            id: id,
            controlType: controlType
        ),
              requestedOperation == expectedOperation else {
            return nil
        }

        return expectedOperation
    }

    /// Returns the compiled operation associated with a shipped Evolution.
    /// This is used solely to migrate a record created before the operation
    /// identifier was introduced; it does not inspect user-authored commands.
    static func curatedPrivilegedOperation(
        id: UUID,
        controlType: ControlType
    ) -> PrivilegedOperation? {
        guard controlType == .Switch else {
            return nil
        }

        return curatedPrivilegedOperations[id]
    }

    func doSwitch() {
        @Dependency(\.evolutionCommandService) var evolutionCommandService
        Task { @MainActor in
            if controlType == .Button {
                guard let singleCommand else { return }
                _ = try? await evolutionCommandService.executeCommand(singleCommand)
                _ = try? await displayNotificationCMD(
                    title: name,
                    content: "",
                    subtitle: "Running".localized()
                )
                .runAppleScript()
            } else {
                guard
                    let statusCommand,
                    let trueCondition = statusCommand.trueCondition,
                    let statusResult = try? await evolutionCommandService.executeCommand(statusCommand)
                else {
                    return
                }

                let isOn = trueCondition == statusResult
                let shouldTurnOn = !isOn
                if shouldTurnOn {
                    _ = try? await evolutionCommandService.executeSwitch(self, enabled: true)
                } else {
                    guard let offCommand else { return }
                    _ = try? await evolutionCommandService.executeSwitch(self, enabled: false)
                }
                _ = try? await displayNotificationCMD(
                    title: name,
                    content: "",
                    subtitle: shouldTurnOn ? "Turn off".localized() : "Turn on".localized()
                )
                .runAppleScript()
            }
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }
}

struct EvolutionCommand: Equatable {
    var executeType: CommandExecuteType = .shell
    var commandType: CommandType
    var commandString: String = ""
    var debugStatus: CommandDebugStatus = .unknow
    var trueCondition: String?
}

enum CommandExecuteType: String, Equatable, Codable {
    case shell, applescript
}

enum CommandType: String, Codable {
    case on, off, single, status

    var typeTitle: String {
        switch self {
            case .on:
                return "Turn on".localized()

            case .off:
                return "Turn off".localized()

            case .single:
                return "Button".localized()

            case .status:
                return "Check status".localized()
        }
    }
}

enum CommandDebugStatus {
    case unknow, failed, success
}

enum EvolutionError: Error, Equatable {
    case noCommand
    case wrongCommand
    case deleteFailed
    case noneEntity
}
