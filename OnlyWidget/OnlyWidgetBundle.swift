//
//  OnlyWidgetBundle.swift
//  OnlyWidget
//
//  Created by Jacklandrin on 2024/2/4.
//

import AppIntents
import OnlyWidgetFeature
import SwiftUI
import Utilities
import WidgetKit

@main
struct OnlyWidgetBundle: WidgetBundle {
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some Widget {
        OnlyWidgetBuildIn()
        OnlyWidgetEvolution()
    }
}

struct OnlyWidgetExtensionPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OnlyWidgetFeaturePackage.self]
    }
}
