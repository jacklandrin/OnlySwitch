//
//  NSEvent++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/19.
//

import AppKit

extension NSEvent {
    var isRightClicked: Bool {
        type == .rightMouseDown || modifierFlags.contains(.control)
    }
}
