//
//  OpenWindow.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import AppKit

enum OpenWindows:String, CaseIterable, CurrentScreen {
    case Setting = "setting"
    case PureColor = "pureColor"
    
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
                settingWindow.setContentSize(NSSize(width: Layout.settingWindowWidth, height: Layout.settingWindowHeight))
                let xPos = getScreenWithMouse()!.frame.width / 2 - Layout.settingWindowWidth / 2
                let yPos = getScreenWithMouse()!.frame.height / 2 - Layout.settingWindowHeight / 2
                settingWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))
                settingWindow.title = "Settings".localized()
                let controller = NSWindowController(window: settingWindow)
                Router.settingWindowController = controller
                controller.showWindow(self)
                settingWindow.makeKeyAndOrderFront(self)
                NSApp.activate(ignoringOtherApps: true)
                
            }
        case .PureColor:
            if let controller = Router.pureColorWindowController {
                controller.showWindow(self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: {
                    controller.window?.toggleFullScreen(self)
                })
            } else {
                let hostingController = NSHostingController(rootView:PureColorView())
                let pureColorWindow = HostWindow(contentViewController: hostingController)
                let width = getScreenWithMouse()!.frame.width
                let height = getScreenWithMouse()!.frame.height
                pureColorWindow.setContentSize(NSSize(width: width, height: height))
                let xPos = width / 2
                let yPos = height / 2
                pureColorWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))
                pureColorWindow.title = "Screen Test".localized()
                pureColorWindow.backgroundColor = NSColor.clear
                let controller = NSWindowController(window: pureColorWindow)
                Router.pureColorWindowController = controller
                controller.showWindow(self)
                pureColorWindow.makeKeyAndOrderFront(self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: {
                    pureColorWindow.toggleFullScreen(self)
                })
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }
}

struct Router {
    static var settingWindowController:NSWindowController?
    static var pureColorWindowController:NSWindowController?
    
    static func isShown(windowController:NSWindowController?) -> Bool {
        windowController?.window?.isVisible ?? false
    }
    
    static func closeWindow(controller:NSWindowController?) {
        controller?.close()
        if controller === pureColorWindowController {
            pureColorWindowController = nil
        }
    }
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

