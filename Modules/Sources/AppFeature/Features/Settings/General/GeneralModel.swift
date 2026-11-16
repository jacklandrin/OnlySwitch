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
    var newestVersion = ""
    var isTheNewestVersion = true
    var supportedLanguages = SupportedLanguages.langList
    var showMenubarIconPopover = false
    var menubarIcons = ["menubar_0", "menubar_1", "menubar_2", "menubar_3"]
    var showErrorToast = false
    var errorInfo = ""
    var showSuccessToast = false
    var successInfo = ""
}
