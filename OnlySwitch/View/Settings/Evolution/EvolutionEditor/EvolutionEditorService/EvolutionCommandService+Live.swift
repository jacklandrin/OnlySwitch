//
//  EvolutionEditorService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import ComposableArchitecture
import Dependencies

extension EvolutionCommandService: DependencyKey {
    static let liveValue = Self (
        executeCommand: { command in
            @Shared(.appStorage("pre-execution")) var preExecution: String?
            guard let command else { throw EvolutionError.noCommand }
            let commandString: String = if let preExecution,
                                           !preExecution.isEmpty,
                                           command.executeType == .shell {
                preExecution + ";" + command.commandString
            } else {
                command.commandString
            }
            return try commandString.runAppleScript(isShellCMD: command.executeType == .shell)
        },
        saveCommand: { item in
            try EvolutionCommandEntity.addItem(item: item)
        },
        saveIcon: { id, icon in
            try EvolutionCommandEntity.updateIcon(name: icon, by: id)
        }
    )
}
