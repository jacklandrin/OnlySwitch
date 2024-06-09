//
//  OnlyWidgetEvolutionProvider.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/6/9.
//

import Extensions
import WidgetKit
import SwiftUI

struct OnlyWidgetEvolutionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OnlyWidgetEvolutionEntry {
        .init(date: .now, content: .init(id: UUID(), title: "Evolution", imageName: "lightswitch.on.square"))
    }

    func snapshot(for configuration: SelectEvolutionIntent, in context: Context) async -> OnlyWidgetEvolutionEntry {
        .init(date: .now, content: EvolutionWidgetModel(id: UUID(), title: "Evolution", imageName: "lightswitch.on.square"))
    }

    func timeline(for configuration: SelectEvolutionIntent, in context: Context) async -> Timeline<OnlyWidgetEvolutionEntry> {
        let entry = OnlyWidgetEvolutionEntry(date: .now, content: configuration.evolution)
        return Timeline(entries: [entry], policy: .never)
    }
}

struct OnlyWidgetEvolutionEntry: TimelineEntry {
    let date: Date
    let content: EvolutionWidgetModel?
}

struct OnlyWidgetEvolutionEntryView: View {
    var entry: OnlyWidgetEvolutionProvider.Entry
    var body: some View {
        if let evolution = entry.content {
            SmallWidget(
                type: .evolution,
                id: evolution.id.uuidString,
                title: evolution.title,
                image: NSImage(systemSymbolName: evolution.imageName ?? "lightswitch.on.square")
            )
        } else {
            ErrorView(unitType: .evolution)
        }
    }
}

struct OnlyWidgetEvolution: Widget {
    let kind: String = "OnlyWidget-Evolution"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectEvolutionIntent.self,
            provider: OnlyWidgetEvolutionProvider()
        ) { entry in
            OnlyWidgetEvolutionEntryView(entry: entry)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Only Widget - Evolution".localized())
        .description("Widgets can control the evolution switches".localized())
        .contentMarginsDisabled()
    }
}
