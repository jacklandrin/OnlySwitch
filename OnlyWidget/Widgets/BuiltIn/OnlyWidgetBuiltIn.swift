//
//  OnlyWidget.swift
//  OnlyWidget
//
//  Created by Jacklandrin on 2024/2/4.
//

import WidgetKit
import SwiftUI
import Switches

struct OnlyWidgetBuiltInProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OnlySwitchBuiltInEntry {
        .init(date: .now, builtInSwitchType: SwitchType.darkMode, id: String(SwitchType.darkMode.rawValue))
    }

    func snapshot(for configuration: SelectBuiltInSwitchesIntent, in context: Context) async -> OnlySwitchBuiltInEntry {
        .init(date: .now, builtInSwitchType: SwitchType.darkMode, id: String(SwitchType.darkMode.rawValue))
    }

    func timeline(for configuration: SelectBuiltInSwitchesIntent, in context: Context) async -> Timeline<OnlySwitchBuiltInEntry> {
        guard let type = configuration.builtInSwitch?.type,
              let id = configuration.builtInSwitch?.id
        else {
            return Timeline(entries: [], policy: .never)
        }
        let entry = OnlySwitchBuiltInEntry(date: .now, builtInSwitchType: type, id: id)
        return Timeline(entries: [entry], policy: .never)
    }
}

struct OnlySwitchBuiltInEntry: TimelineEntry {
    let date: Date
    let builtInSwitchType: SwitchType
    let id: String
}

struct OnlyWidgetBuiltInEntryView: View {
    var entry: OnlyWidgetBuiltInProvider.Entry
    var body: some View {
        SmallWidget(
            id: entry.id,
            title: entry.builtInSwitchType.barInfo().title,
            image: entry.builtInSwitchType.barInfo().onImage
        )
    }
}

struct OnlyWidgetBuildIn: Widget {
    let kind: String = "OnlyWidget-BuiltIn"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectBuiltInSwitchesIntent.self,
            provider: OnlyWidgetBuiltInProvider()
        ) { entry in
            OnlyWidgetBuiltInEntryView(entry: entry)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Only Widget - BuiltIn".localized())
        .description("Widgets can control the built-in switches".localized())
        .contentMarginsDisabled()
    }
}
