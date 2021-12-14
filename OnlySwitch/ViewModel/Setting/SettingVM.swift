//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI

let changeSettingNotification = NSNotification.Name("changeSettingNotification")
enum SettingItem:String {
    case AirPods = "AirPods"
    case Radio = "Radio"
    case General = "General"
    case About = "About"
    
    func page() -> AnyView {
        switch self {
        case .AirPods:
            return AnyView(AirPodsSettingView())
        case .Radio:
            return AnyView(RadioSettingView())
        case .General:
            return AnyView(GeneralView())
        case .About:
            return AnyView(AboutView())
        }
    }
}

class SettingVM:ObservableObject {
    @Published var settingItems:[SettingItem] = [.General,.Radio,.AirPods,.About]
    @Published var selection:SettingItem?
}
