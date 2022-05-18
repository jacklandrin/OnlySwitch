//
//  NSImage+SymbolName.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/18.
//

import AppKit
extension NSImage {
    public convenience init(systemSymbolName:String) {
        self.init(systemSymbolName: systemSymbolName, accessibilityDescription:nil)!
    }
}
