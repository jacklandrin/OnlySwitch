//
//  SelectSwitchesIntent.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/2/13.
//

import AppIntents
import Switches
import WidgetKit

struct SelectBuildInSwitchesIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Build-In Switches"
    static var description: LocalizedStringResource = "Select the switches you want to display in the widget."
    @Parameter(title: "Switch")
    var buildInSwitch: BuildInSwitchEntity
    init(buildInSwitch: BuildInSwitchEntity) {
        self.buildInSwitch = buildInSwitch
    }
    init() { }
}
