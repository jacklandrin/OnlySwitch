//
//  GeneralModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/23.
//

import Foundation

struct GeneralModel {
    var cacheSize:String = ""
    var needtoUpdateAlert = false
    var showProgress = false
    var newestVersion = UserDefaults.standard.string(forKey: newestVersionKey) ?? ""
    var supportedLanguages = SupportedLanguages.langList
    var showMenubarIconPopover = false
    var menubarIcons = ["menubar_0", "menubar_1", "menubar_2", "menubar_3"]
}
