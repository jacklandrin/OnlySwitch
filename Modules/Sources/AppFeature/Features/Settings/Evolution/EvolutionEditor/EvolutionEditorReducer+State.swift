//
//  EvolutionEditorReducer+State.swift
//  OnlySwitch
//

import Foundation
import Switches

extension EvolutionEditorReducer.State {
    var isDirty: Bool {
        Self.normalized(makeItem()) != Self.normalized(original)
    }

    var missingRequirements: [EvolutionEditorReducer.Requirement] {
        var missing: [EvolutionEditorReducer.Requirement] = []
        if evolution.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append(.name)
        }
        for state in commandStates {
            let command = state.command
            if command.commandString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(.script(command.commandType))
            } else if command.commandType != .status, !isVerified(command) {
                missing.append(.test(command.commandType))
            }
            if command.commandType == .status, needsOnOutput(command) {
                missing.append(.statusOnOutput)
            }
        }
        return missing
    }

    var canSave: Bool {
        !isSaving && (isNew || isDirty) && missingRequirements.isEmpty
    }

    var hasScripts: Bool {
        commandStates.contains { !$0.command.commandString.isEmpty }
    }

    /// The item to persist. Commands that are unchanged from the saved version
    /// count as verified: they passed a test when they were first saved, and
    /// re-testing would toggle the user's system just to rename an Evolution.
    func makeItem() -> EvolutionItem {
        var item = evolution
        for state in commandStates {
            var command = state.command
            let saved = savedCommand(command.commandType)
            if saved == nil, command.commandString.isEmpty, command.trueCondition?.isEmpty ?? true {
                assign(nil, to: command.commandType, in: &item)
                continue
            }
            if command.debugStatus != .failed, isUnchanged(command) {
                command.debugStatus = .success
            }
            assign(command, to: command.commandType, in: &item)
        }
        return item
    }

    func savedCommand(_ type: CommandType) -> EvolutionCommand? {
        guard original.controlType == evolution.controlType else { return nil }
        switch type {
        case .on: return original.onCommand
        case .off: return original.offCommand
        case .status: return original.statusCommand
        case .single: return original.singleCommand
        }
    }

    func isUnchanged(_ command: EvolutionCommand) -> Bool {
        guard !isNew, let saved = savedCommand(command.commandType) else { return false }
        return saved.commandString == command.commandString && saved.executeType == command.executeType
    }

    func isVerified(_ command: EvolutionCommand) -> Bool {
        command.debugStatus == .success || (command.debugStatus != .failed && isUnchanged(command))
    }

    private func needsOnOutput(_ command: EvolutionCommand) -> Bool {
        let condition = command.trueCondition ?? ""
        guard condition.isEmpty else { return false }
        // A legacy switch may deliberately treat empty output as "on".
        return !(savedCommand(.status)?.trueCondition == "" && isUnchanged(command))
    }

    private func assign(_ command: EvolutionCommand?, to type: CommandType, in item: inout EvolutionItem) {
        switch type {
        case .on: item.onCommand = command
        case .off: item.offCommand = command
        case .status: item.statusCommand = command
        case .single: item.singleCommand = command
        }
    }

    private static func normalized(_ item: EvolutionItem) -> EvolutionItem {
        var item = item
        for keyPath in [\EvolutionItem.onCommand, \.offCommand, \.statusCommand, \.singleCommand] {
            item[keyPath: keyPath]?.debugStatus = .unknow
        }
        return item
    }
}
