//
//  OnlyWidget.swift
//  OnlyWidget
//
//  Created by Jacklandrin on 2024/2/4.
//

import WidgetKit
import SwiftUI
import Switches

struct OnlyWidgetBuildInProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OnlySwitchBuildInEntry {
        .init(date: .now, buildInSwitchType: SwitchType.darkMode, id: String(SwitchType.darkMode.rawValue))
    }

    func snapshot(for configuration: SelectBuildInSwitchesIntent, in context: Context) async -> OnlySwitchBuildInEntry {
        .init(date: .now, buildInSwitchType: SwitchType.darkMode, id: String(SwitchType.darkMode.rawValue))
    }

    func timeline(for configuration: SelectBuildInSwitchesIntent, in context: Context) async -> Timeline<OnlySwitchBuildInEntry> {
        let entry = OnlySwitchBuildInEntry(date: .now, buildInSwitchType: configuration.buildInSwitch.type, id: configuration.buildInSwitch.id)
        return Timeline(entries: [entry], policy: .never)
    }
}

struct OnlySwitchBuildInEntry: TimelineEntry {
    let date: Date
    let buildInSwitchType: SwitchType
    let id: String
}

struct OnlyWidgetEntryView : View {
    var entry: OnlyWidgetBuildInProvider.Entry
    var body: some View {
        SmallWidget(
            id: entry.id,
            title: entry.buildInSwitchType.barInfo().title,
            image: entry.buildInSwitchType.barInfo().onImage
        )
    }
}

struct OnlyWidgetBuildIn: Widget {
    let kind: String = "OnlyWidget-BuildIn"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectBuildInSwitchesIntent.self,
            provider: OnlyWidgetBuildInProvider()
        ) { entry in
            OnlyWidgetEntryView(entry: entry)
                .containerBackground(.fill.quaternary, for: .widget)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Only Widget - BuildIn".localized())
        .description("Widgets can control the build-in switches".localized())
        .contentMarginsDisabled()
    }
}
