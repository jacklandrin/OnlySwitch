//
//  SelectEvolutionIntent.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/6/9.
//

import AppIntents
import WidgetKit

struct SelectEvolutionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Evolution"
    static let description: LocalizedStringResource = "Select Evolution you want to display in the widget."
    @Parameter(title: "Evolution")
    var evolutionEntity: EvolutionEntity?

    var evolution: EvolutionWidgetModel? {
        evolutionEntity?.evolution
    }

    init(evolutionEntity: EvolutionEntity) {
        self.evolutionEntity = evolutionEntity
    }

    init() { }
}
