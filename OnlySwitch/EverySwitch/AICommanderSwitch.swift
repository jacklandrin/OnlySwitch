//
//  AICommanderSwitch.swift
//  OnlySwitch
//
//  Created by Bo Liu on 16.11.25.
//

import Switches
import Defines
import OnlyAgent
import AppKit
import SwiftUI

final class AICommanderSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .aiCommender
    
    private lazy var eventMonitor : EventMonitor = {
        EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)
    }()
    
    private var promptDialogueWindow: NSWindow?
    
    private var isWindowPresented: Bool {
        promptDialogueWindow?.isVisible == true
    }
    
    @MainActor
    func currentStatus() async -> Bool {
        isWindowPresented
    }
    
    @MainActor
    func currentInfo() async -> String {
        ""
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            showWindow()
            NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
        } else {
            hideWindow()
        }
    }
    
    func isVisible() -> Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    private func makeWindow() -> PromptDialogueWindow {
        let window = PromptDialogueWindow(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: .main
        )
        let contentRect = window.contentRect(forFrameRect: window.frame)
        if #available(macOS 26.0, *) {
            let view = NSHostingView(rootView: PromptDialogueView(store: .init(initialState: .init(), reducer: PromptDialogueReducer.init)))
            view.frame = contentRect
            view.canDrawSubviewsIntoLayer = true
            window.contentView = view
        }

        [window].forEach {
            $0.isMovable = true
            $0.collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
            $0.level = .mainMenu
            $0.ignoresMouseEvents = false
            $0.hasShadow = true
            $0.isReleasedWhenClosed = false
            $0.backgroundColor = .clear
            $0.isMovableByWindowBackground = true
            $0.isOpaque = false
        }

        window.makeKeyAndOrderFront(nil)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            
            let x = visible.origin.x + (visible.width - Layout.promptDialogWidth) / 2.0
            let y = visible.origin.y + 130.0
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.setIsVisible(false)
        return window
    }
    
    private func showWindow() {
        if promptDialogueWindow == nil {
            promptDialogueWindow = makeWindow()
        }
        promptDialogueWindow?.makeKeyAndOrderFront(nil)
        eventMonitor.start()
    }
    
    private func hideWindow() {
        promptDialogueWindow?.close()
        promptDialogueWindow = nil
        eventMonitor.stop()
    }
    
    private func mouseEventHandler(_ event: NSEvent?) {
        if isWindowPresented {
            hideWindow()
        } else {
            showWindow()
        }
    }
}

final class PromptDialogueWindow: NSWindow, NSWindowDelegate {
    override var canBecomeKey: Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
