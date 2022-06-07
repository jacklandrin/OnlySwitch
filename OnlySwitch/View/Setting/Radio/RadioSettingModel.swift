//
//  RadioSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

struct RadioSettingModel {
    var radioList:[RadioPlayerItem] = [RadioPlayerItem]()
    var selectRow:RadioPlayerItem.ID?
    var showErrorToast = false
    var errorInfo = ""
    var currentTitle = ""
}
