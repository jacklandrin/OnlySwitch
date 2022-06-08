//
//  NSView++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/9.
//

import Foundation
import AppKit
extension NSView {
    var getOrigin:CGPoint? {
        return self.window?.frame.origin
    }
}
