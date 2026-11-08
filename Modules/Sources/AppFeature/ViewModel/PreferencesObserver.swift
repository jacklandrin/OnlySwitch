//
//  PreferencesPublisher.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/5.
//

import Foundation

@MainActor
class PreferencesObserver:ObservableObject {
    static let shared = PreferencesObserver()
    @Published var preferences = Preferences.shared
}
