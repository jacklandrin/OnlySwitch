//
//  SelectSwitchesIntent.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/2/13.
//

import AppIntents
import Switches
import WidgetKit
import Extensions

struct SelectBuiltInSwitchesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Built-In Switches"
    static let description: LocalizedStringResource = "Select the switches you want to display in the widget."
    @Parameter(title: "Built-In Switch")
    var builtInSwitch: BuiltInSwitchEntity?
    init(builtInSwitch: BuiltInSwitchEntity) {
        self.builtInSwitch = builtInSwitch
    }
    init() { }
}
