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
    
    func page() -> AnyView {
        switch self {
        case .AirPods:
            return AnyView(Text("AirPods"))
        case .Radio:
            return AnyView(RadioSetting())
        }
    }
}

class SettingVM:ObservableObject {
    @Published var settingItems:[SettingItem] = [.AirPods,.Radio]
    @Published var selection:SettingItem?
}
