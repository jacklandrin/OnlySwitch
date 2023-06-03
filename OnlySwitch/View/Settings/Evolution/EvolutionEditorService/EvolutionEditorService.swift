//
//  EvolutionEditorService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Foundation

struct EvolutionEditorService {
    var executeCommand: @Sendable (EvolutionCommand?) throws -> String
}
