//
//  EvolutionEditorService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies

extension EvolutionEditorService: DependencyKey {
    static let liveValue = Self (
        executeCommand: { command in
            guard let command else {throw EvolutionError.noCommand}
            return try command.commandString.runAppleScript(isShellCMD: command.executeType == .shell)
        },
        saveCommand: { item in
            try EvolutionCommandEntity.addItem(item: item)
        }
    )
}
