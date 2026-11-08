//
//  OnlyControlWindow.swift
//  OnlySwitch
//

import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class OnlyControlWindow: NSWindow, NSWindowDelegate {
    static let shared = OnlyControlWindow()

    private static let contentSize = NSSize(width: 820, height: 620)
    private static let frameAutosaveName = "OnlyControlWindow"

    private(set) var isShowing = false
    var onVisibilityChanged: ((Bool) -> Void)?
    var outsideClickExclusionWindowNumbers = Set<Int>()

    private let onlyControlStore: StoreOf<OnlyControlReducer> = .init(initialState: .init()) {
        OnlyControlReducer()
    } withDependencies: {
        $0.systemMonitor = MacSystemMonitorCollector.liveClient()
    }
    var preventsOutsideClickDismissal: Bool {
        !onlyControlStore.selectedSection.allowsOutsideClickDismissal
    }
    var selectedSection: SectionBar.Section {
        onlyControlStore.selectedSection
    }

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hideTask: Task<Void, Never>?

    override var canBecomeKey: Bool {
        true
    }

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setupWindow()
    }

    private func setupWindow() {
        let view = OnlyControlHostingView(rootView: OnlyControlView(store: onlyControlStore))
        setContentSize(Self.contentSize)
        view.frame = contentRect(forFrameRect: frame)
        view.canDrawSubviewsIntoLayer = true
        contentView = view

        isMovable = true
        collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
        level = .mainMenu
        ignoresMouseEvents = false
        hasShadow = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        isOpaque = false
        delegate = self

        makeKeyAndOrderFront(nil)
        center()
        setIsVisible(false)
    }

    func show(monitorsOutsideClicks: Bool = false) {
        hideTask?.cancel()
        hideTask = nil
        restoreFrame()
        makeKeyAndOrderFront(nil)
        setShowing(true)
        if monitorsOutsideClicks {
            startOutsideClickMonitoring()
        } else {
            stopOutsideClickMonitoring()
        }
        onlyControlStore.send(.showControl)
    }

    func hide(completion: (() -> Void)? = nil) {
        guard isShowing else {
            completion?()
            return
        }

        setShowing(false)
        stopOutsideClickMonitoring()
        onlyControlStore.send(.hideControl)

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(510))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.close()
            self.hideTask = nil
            completion?()
        }
    }

    func toggle(monitorsOutsideClicks: Bool = false) {
        isShowing ? hide() : show(monitorsOutsideClicks: monitorsOutsideClicks)
    }

    private func setShowing(_ newValue: Bool) {
        guard isShowing != newValue else { return }
        isShowing = newValue
        onVisibilityChanged?(newValue)
    }

    private func restoreFrame() {
        let restoredSavedFrame = setFrameUsingName(Self.frameAutosaveName)
        setContentSize(Self.contentSize)
        guard let screen = screenContainingWindow ?? NSScreen.main else {
            center()
            setFrameAutosaveName(Self.frameAutosaveName)
            return
        }

        if restoredSavedFrame {
            setFrame(constrainFrameRect(frame, to: screen), display: false)
        } else {
            center()
        }

        setFrameAutosaveName(Self.frameAutosaveName)
    }

    private var screenContainingWindow: NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
    }

    private func startOutsideClickMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissForOutsideClick()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleLocalMouseDown(event)
            }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard event.windowNumber != windowNumber,
              !outsideClickExclusionWindowNumbers.contains(event.windowNumber) else {
            return
        }
        dismissForOutsideClick()
    }

    private func dismissForOutsideClick() {
        guard !preventsOutsideClickDismissal else { return }
        hide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}

/// Lets AppKit handle window movement for every non-control portion of the
/// hosting hierarchy. Native controls and scroll views still receive their
/// normal events before the background drag behavior applies.
private final class OnlyControlHostingView: NSHostingView<OnlyControlView> {
    override var mouseDownCanMoveWindow: Bool { true }
}
