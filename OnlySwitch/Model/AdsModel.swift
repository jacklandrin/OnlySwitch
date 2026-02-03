//
//  AdsModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/2.
//

import Foundation

struct AdsModel:Identifiable{
    var id = UUID()
    let imageName:String
    let link:String
    let hint:String
}

let Ads:[AdsModel] = [
    AdsModel(
        imageName: "QRCobot",
        link: "https://apps.apple.com/us/app/id1590006394",
        hint: "Download QRCobot"
    ),
    AdsModel(
        imageName: "OnlyBaby",
        link: "https://apps.apple.com/us/app/onlybaby/id6758526534",
        hint: "Download OnlyBaby"
    ),
    AdsModel(
        imageName: "illa",
        link: "https://github.com/illacloud/illa-builder",
        hint: "illa Builder"
    ),
    AdsModel(
        imageName: "CalendarX",
        link: "https://github.com/ZzzM/CalendarX",
        hint: "CalendarX"
    ),
    AdsModel(
        imageName: "hdwh",
        link: "https://hdwh.de/",
        hint: "hdwh"
    )
]
