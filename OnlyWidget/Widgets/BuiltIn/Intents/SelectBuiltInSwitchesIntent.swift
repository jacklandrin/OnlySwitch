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
    static var title: LocalizedStringResource = "Select Built-In Switches"
    static var description: LocalizedStringResource = "Select the switches you want to display in the widget."
    @Parameter(title: "Built-In Switch")
    var builtInSwitch: BuiltInSwitchEntity?
    init(builtInSwitch: BuiltInSwitchEntity) {
        self.builtInSwitch = builtInSwitch
    }
    init() { }
}
