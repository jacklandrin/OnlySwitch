//
//  EvolutionListService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Foundation

struct EvolutionListService {
    /// Loads saved Evolutions with `active` reflecting whether each is shown in the menu.
    var loadEvolutionList: @Sendable () async throws -> [EvolutionItem]
    var removeItem: @Sendable (UUID) async throws -> Void
    /// Shows or hides an Evolution in the OnlySwitch menu.
    var setActive: @Sendable (UUID, Bool) async -> Void = { _, _ in }
}
