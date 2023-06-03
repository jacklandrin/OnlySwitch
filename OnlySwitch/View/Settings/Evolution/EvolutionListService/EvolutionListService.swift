//
//  EvolutionListService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Foundation

struct EvolutionListService {
    var loadEvolutionList: @Sendable () async throws -> [EvolutionItem]
}
