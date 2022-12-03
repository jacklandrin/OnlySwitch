//
//  RadioSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

struct RadioSettingModel {
    var radioList:[RadioPlayerItemViewModel] = [RadioPlayerItemViewModel]()
    var selectRow:RadioPlayerItemViewModel.ID?
    var showErrorToast = false
    var errorInfo = ""
    var currentTitle = ""
}
