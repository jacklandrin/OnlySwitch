//
//  AICommanderSwitch.swift
//  OnlySwitch
//
//  Created by Bo Liu on 16.11.25.
//

import ComposableArchitecture
import Switches
import Defines
import OnlyAgent
import AppKit
import SwiftUI
import Sharing

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
    private var _store: Any?
    
    @MainActor
    @available(macOS 26.0, *)
    var store: StoreOf<PromptDialogueReducer> {
        if _store == nil {
            _store = makeStore()
        }
        return _store as! StoreOf<PromptDialogueReducer>
    }
    
    @MainActor
    @available(macOS 26.0, *)
    private func makeStore() -> StoreOf<PromptDialogueReducer> {
        return .init(initialState: .init(), reducer: PromptDialogueReducer.init)
    }
    
    @MainActor
    func currentStatus() async -> Bool {
        isWindowPresented
    }
    
    @MainActor
    func currentInfo() async -> String {
        if #available(macOS 26.0, *) {
            @Shared(.currentAIModel) var currentAIModel: CurrentAIModel?
            return currentAIModel?.model ?? ""
        }
        return ""
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            await showWindow()
            NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
        } else {
            await hideWindow()
        }
    }
    
    func isVisible() -> Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    @MainActor
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
            let view = NSHostingView(rootView: PromptDialogueView(store: store))
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
            $0.isOpaque = false
        }

        window.makeKeyAndOrderFront(nil)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            
            let x = visible.origin.x + (visible.width - Layout.promptDialogWidth) / 2.0
            let y = visible.origin.y + 150.0
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.setIsVisible(false)
        return window
    }
    
    @MainActor
    private func showWindow() async {
        if promptDialogueWindow == nil {
            promptDialogueWindow = makeWindow()
        }
        promptDialogueWindow?.makeKeyAndOrderFront(nil)
        eventMonitor.start()
    }
    
    @MainActor
    private func hideWindow() async {
        guard #available(macOS 26.0, *), store.prompt.isEmpty else {
            return
        }
        promptDialogueWindow?.close()
        promptDialogueWindow = nil
        eventMonitor.stop()
    }
    
    private func mouseEventHandler(_ event: NSEvent?) {
        Task {
            if isWindowPresented {
                await hideWindow()
            } else {
                await showWindow()
            }
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
