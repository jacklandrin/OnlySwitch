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

/// Hosts the Only Agent conversation window. The window is opened from the
/// switch list or from Evolution settings and keeps its conversation while hidden.
final class AICommanderSwitch: SwitchProvider, @unchecked Sendable {
    static let shared = AICommanderSwitch()

    weak var delegate: SwitchDelegate?
    var type: SwitchType = .aiCommender

    private lazy var eventMonitor: EventMonitor = {
        EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.mouseEventHandler(event)
        }
    }()

    private var agentWindow: NSWindow?
    private var _store: Any?
    private var _closingState: Any?

    private init() {}

    @MainActor
    private var isWindowPresented: Bool {
        agentWindow?.isVisible == true
    }

    @MainActor
    @available(macOS 26.0, *)
    var store: StoreOf<AgentConversationReducer> {
        if let store = _store as? StoreOf<AgentConversationReducer> {
            return store
        }
        let store = Store(initialState: AgentConversationReducer.State()) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentEvolutionClient = .app
        }
        _store = store
        return store
    }

    @MainActor
    @available(macOS 26.0, *)
    private var closingState: AgentWindowClosingState {
        if let state = _closingState as? AgentWindowClosingState {
            return state
        }
        let state = AgentWindowClosingState()
        _closingState = state
        return state
    }

    @MainActor
    func currentStatus() async -> Bool {
        isWindowPresented
    }

    @MainActor
    func currentInfo() async -> String {
        @Shared(.currentAIModel) var currentAIModel: CurrentAIModel?
        return currentAIModel?.model ?? ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            await present()
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

    /// Shows the Only Agent window; used by the switch and by Evolution settings.
    @MainActor
    func present() async {
        guard #available(macOS 26.0, *) else { return }
        await showWindow()
        NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
    }

    @MainActor
    @available(macOS 26.0, *)
    private func makeWindow() -> AgentConversationWindow {
        let size = NSSize(width: Layout.onlyAgentWindowWidth, height: Layout.onlyAgentWindowHeight)
        let window = AgentConversationWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: .main
        )
        let view = NSHostingView(rootView: AgentWindowRoot(store: store, closingState: closingState))
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        window.isMovable = true
        window.collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
        window.level = .mainMenu
        window.ignoresMouseEvents = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.origin.x + (visible.width - size.width) / 2.0
            let y = visible.origin.y + max(40, (visible.height - size.height) / 2.0)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        return window
    }

    @MainActor
    @available(macOS 26.0, *)
    private func showWindow() async {
        if agentWindow == nil {
            agentWindow = makeWindow()
        }
        closingState.isClosing = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        agentWindow?.makeKeyAndOrderFront(nil)
        eventMonitor.start()
    }

    @MainActor
    private func hideWindow() async {
        guard #available(macOS 26.0, *), agentWindow != nil, store.canDismiss else {
            return
        }
        closingState.isClosing = true
        try? await Task.sleep(for: .milliseconds(420))
        // The user may have reopened the window during the fade-out.
        guard closingState.isClosing else { return }
        agentWindow?.orderOut(nil)
        eventMonitor.stop()
    }

    private func mouseEventHandler(_ event: NSEvent?) {
        Task { @MainActor in
            if isWindowPresented {
                await hideWindow()
            } else {
                await present()
            }
        }
    }
}

@available(macOS 26.0, *)
@MainActor
@Observable
final class AgentWindowClosingState {
    var isClosing = false
}

@available(macOS 26.0, *)
private struct AgentWindowRoot: View {
    let store: StoreOf<AgentConversationReducer>
    let closingState: AgentWindowClosingState

    var body: some View {
        AgentConversationView(store: store, isClosing: closingState.isClosing)
    }
}

final class AgentConversationWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}
