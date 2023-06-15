//
//  EvolutionModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Foundation

struct EvolutionItem: Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var active = false
    var controlType: ControlType = .Switch
    var onCommand: EvolutionCommand?
    var offCommand: EvolutionCommand?
    var singleCommand: EvolutionCommand?
    var statusCommand: EvolutionCommand?

    func doSwitch() {
        if controlType == .Button {
            guard let singleCommand else { return }
            _ = try? singleCommand.commandString.runAppleScript(isShellCMD: singleCommand.executeType == .shell)
        } else {
            guard
                let statusCommand,
                let trueCondition = statusCommand.trueCondition,
                let statusResult = try? statusCommand.commandString.runAppleScript(isShellCMD: statusCommand.executeType == .shell)
            else {
                return
            }

            let isOn = trueCondition == statusResult

            if isOn {
                guard let onCommand else { return }
                _ = try? onCommand.commandString.runAppleScript(isShellCMD: onCommand.executeType == .shell)
            } else {
                guard let offCommand else { return }
                _ = try? offCommand.commandString.runAppleScript(isShellCMD: offCommand.executeType == .shell)
            }

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
}


