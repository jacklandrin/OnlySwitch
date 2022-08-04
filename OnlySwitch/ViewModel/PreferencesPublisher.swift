//
//  PreferencesPublisher.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/5.
//

import Foundation

class PreferencesPublisher:ObservableObject {
    static var shared = PreferencesPublisher()
    @Published var preferences = Preferences.shared
}
