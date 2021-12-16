//
//  OpenWindow.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import AppKit

enum OpenWindows:String, CaseIterable {
    case Setting = "setting"
    
    func open() {
        let persistenceController = PersistenceController.shared
        switch self {
        case .Setting:
            if let controller = Router.settingWindowController {
                controller.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                let hostingController = NSHostingController(rootView:SettingView().environment(\.managedObjectContext, persistenceController.container.viewContext))
                let settingWindow = HostWindow(contentViewController: hostingController)
                settingWindow.setContentSize(NSSize(width: settingWindowWidth, height: settingWindowHeight))
                let xPos = getScreenWithMouse()!.frame.width / 2 - settingWindowWidth / 2
                let yPos = getScreenWithMouse()!.frame.height / 2 - settingWindowHeight / 2
                settingWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))
                settingWindow.title = "Settings".localized()
                let controller = NSWindowController(window: settingWindow)
                Router.settingWindowController = controller
                controller.showWindow(self)
                settingWindow.makeKeyAndOrderFront(self)
                NSApp.activate(ignoringOtherApps: true)
                
            }
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    
    private func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        return screenWithMouse
    }
}

struct Router {
    static var settingWindowController:NSWindowController?
}

class HostWindow:NSWindow, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("close window")
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first!.makeKeyAndOrderFront(self)
        }
        return true
    }
}

