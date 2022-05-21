//
//  CGKeyCode++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/22.
//

import CoreGraphics
extension CGKeyCode {
    static let kVK_LeftArrow: CGKeyCode = 0x7B
    static let kVK_RightArrow: CGKeyCode = 0x7C
    
    var isPressed: Bool {
        CGEventSource.keyState(.combinedSessionState, key: self)
    }
}

