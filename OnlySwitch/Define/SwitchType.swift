//
//  SwitchType.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import AppKit

struct SwitchBarInfo {
    let title:String
    let onImage:NSImage
    let offImage:NSImage
}

enum SwitchType:Int {
    case hiddeDesktop = 1
    case darkMode
    case topNotch
    case mute
    case keepAwake
    case screenSaver
    case nightShift
    case autohideDock
    case autohideMenuBar
    case airPods
    case bluetooth
    case xcodeCache
    case hiddenFiles
    case radioStation
}
