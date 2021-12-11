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
    case About = "About"
    
    func page() -> AnyView {
        switch self {
        case .AirPods:
            return AnyView(AirPodsSettingView())
        case .Radio:
            return AnyView(RadioSettingView())
        case .About:
            return AnyView(AboutView())
        }
    }
}

class SettingVM:ObservableObject {
    @Published var settingItems:[SettingItem] = [.Radio,.AirPods,.About]
    @Published var selection:SettingItem?
}
