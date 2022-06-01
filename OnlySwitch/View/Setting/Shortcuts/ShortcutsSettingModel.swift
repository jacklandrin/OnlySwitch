//
//  ShortcutsSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/26.
//

import Foundation

struct ShortcutsSettingModel {
    var shortcutsList : [ShortcutsItem] = [ShortcutsItem]()
    var errorInfo = ""
    var showErrorToast = false
    var sharedShortcutsList:[SharedShortcutsItem] = [SharedShortcutsItem]()
}


