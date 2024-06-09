//
//  OnlyWidgetBundle.swift
//  OnlyWidget
//
//  Created by Jacklandrin on 2024/2/4.
//

import SwiftUI
import WidgetKit
import Utilities

@main
struct OnlyWidgetBundle: WidgetBundle {
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some Widget {
        OnlyWidgetBuildIn()
        OnlyWidgetEvolution()
    }
}
