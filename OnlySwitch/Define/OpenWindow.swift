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
            let hostingController = NSHostingController(rootView:SettingView().environment(\.managedObjectContext, persistenceController.container.viewContext))
            let settingWindow = NSWindow(contentViewController: hostingController)
            settingWindow.setContentSize(NSSize(width: settingWindowWidth, height: settingWindowHeight))
            let xPos = getScreenWithMouse()!.frame.width / 2 - settingWindowWidth / 2
            let yPos = getScreenWithMouse()!.frame.height / 2 - settingWindowHeight / 2
            settingWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))
            let controller = NSWindowController(window: settingWindow)
            controller.showWindow(self)
            settingWindow.makeKeyAndOrderFront(self)
            NSApp.activate(ignoringOtherApps: true)
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
