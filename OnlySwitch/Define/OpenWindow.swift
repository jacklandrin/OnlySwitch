//
//  OpenWindow.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import Defines
import SwiftUI
import AppKit
import Networking

@MainActor
enum OpenWindows: CurrentScreen {
    case Update(GitHubPresenter)
    
    func open() {
        switch self {
        case .Update(let presenter):
            let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 320, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
            window.center()
            window.contentView = NSHostingView(rootView: UpdateView(presenter:presenter,
                                                                    updateWindow: window))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        
    }
}
