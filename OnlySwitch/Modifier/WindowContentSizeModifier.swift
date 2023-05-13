//
//  WindowResizabilityModifier.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/13.
//

import SwiftUI

extension Scene {
    
    func windowKeepContentSize() -> some Scene {
        if #available(macOS 13.3, *) {
            return self.windowResizability(.contentSize)
        }
        return self
    }
}
