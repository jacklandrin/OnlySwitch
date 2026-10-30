//
//  RadioSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

///for export/import
struct RadioItem:Codable {
    let name:String
    let url:String
    enum CodingKeys:String, CodingKey {
        case name
        case url
    }
}
