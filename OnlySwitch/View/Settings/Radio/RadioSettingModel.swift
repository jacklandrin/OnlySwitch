//
//  RadioSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

struct RadioSettingModel {
    var radioList: [RadioPlayerItemViewModel] = [RadioPlayerItemViewModel]()
    var selectRow:RadioPlayerItemViewModel.ID?
    var showSuccessToast = false
    var successInfo = ""
    var showErrorToast = false
    var errorInfo = ""
    var currentTitle = ""
    var isTipPopover = false
}

///for export/import
struct RadioItem:Codable {
    let name:String
    let url:String
    enum CodingKeys:String, CodingKey {
        case name
        case url
    }
}
