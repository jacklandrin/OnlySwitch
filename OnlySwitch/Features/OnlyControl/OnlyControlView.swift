//
//  OnlyControlView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/8/27.
//

import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import OnlyControl
import Defines
import Extensions
import Foundation
import SystemMonitor

struct OnlyControlView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: StoreOf<OnlyControlReducer>
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @State private var currentDate = Date()
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(store: StoreOf<OnlyControlReducer>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    BluredSoundWave(width: 800, height: 200)
                        .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                        .opacity(0.9)
                        .isHidden(!store.soundWaveEffectDisplay || !playerItem.isPlaying, remove: true)
                }

                VStack(spacing: 0) {
                    OnlyControlSectionBar(selection: selectedSection)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    sectionContent
                }
            }
            .cornerRadius(15)
            .blur(radius: store.blurRadius)
            .opacity(store.opacity)
            .animation(.interactiveSpring(duration: 0.5), value: store.blurRadius)
            .frame(width: 800, height: 600)
            .ignoresSafeArea()
            .padding(10)
            .task {
                store.send(.task)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.selectedSection {
            case .controls:
                controlsPage
            case .systemMonitor:
                systemMonitorPage
            default:
                EmptyView()
        }
    }

    private var controlsPage: some View {
        VStack(spacing: 0) {
            controlHeader
                .padding(.horizontal, 30)
                .padding(.top, 12)

            DashboardView(store: store.scope(state: \.dashboard, action: \.dashboardAction))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }

    private var systemMonitorPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                SystemMonitorPanelView(
                    store: store.scope(state: \.systemMonitor, action: \.systemMonitor)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }

    private var controlHeader: some View {
        HStack(alignment: .bottom) {
            Text(currentDate, style: .time)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .onReceive(timer) { _ in
                    currentDate = Date()
                }

            if store.isAirPodsConnected && !store.airPodsBatteryValues.isEmpty {
                AirPodsBatteryView(batteryValues: store.airPodsBatteryValues)
                    .padding(.bottom, 8)
                    .padding(.leading, 24)
            }

            Spacer(minLength: 16)

            TimerCountDownView(ptswitch: PomodoroTimerSwitch.shared, showImage: true)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if playerItem.streamInfo.isEmpty {
                Text("Only Switch".localized())
                    .bold()
                Text("v\(SystemInfo.majorVersion as! String)")
                    .foregroundStyle(.secondary)
            } else {
                RollingText(
                    text: playerItem.streamInfo,
                    leftFade: 16,
                    rightFade: 16,
                    startDelay: 3
                )
                .frame(height: 20)
            }
            Spacer()
            Button("Settings".localized(), systemImage: "gear") {
                store.send(.openSettings)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help(Text("Settings".localized()))
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    private var selectedSection: Binding<SectionBar.Section> {
        Binding(
            get: { store.selectedSection },
            set: { store.send(.selectedSectionChanged($0)) }
        )
    }
}

private struct OnlyControlSectionBar: View {
    @Binding var selection: SectionBar.Section

    var body: some View {
        HStack(spacing: 4) {
            sectionButton(.controls, title: "Controls".localized(), icon: "switch.2")
            sectionButton(.systemMonitor, title: "System Monitor".localized(), icon: "waveform.path.ecg")
        }
        .padding(4)
        .background(.black.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Only Control sections".localized())
    }

    private func sectionButton(
        _ section: SectionBar.Section,
        title: String,
        icon: String
    ) -> some View {
        Button {
            selection = section
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == section ? Color.accentColor : .secondary)
        .background {
            if selection == section {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    }
            }
        }
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityHint("Shows the \(title) section".localized())
        .help(Text(title))
    }
}

#Preview {
    OnlyControlView(store: .init(initialState: .init()) {
        OnlyControlReducer()
    })
}

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
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hideTask: Task<Void, Never>?

    override var canBecomeKey: Bool {
        true
    }

    /// `NSScrollView` owns its clip and document views, including visual gaps
    /// between dashboard tiles. Route a click in that otherwise unused canvas
    /// to AppKit's normal window drag handling, without intercepting controls,
    /// text, or gesture-driven content inside the scroll view.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isBlankScrollCanvasClick(event) {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
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

    private func isBlankScrollCanvasClick(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return false }

        let hierarchy = Array(sequence(first: hitView, next: \.superview))
        guard let scrollView = hierarchy.compactMap({ $0 as? NSScrollView }).first else {
            return false
        }

        // SwiftUI can attach a recognizer to the document hosting view itself.
        // That recognizer covers the full document bounds, including whitespace,
        // so only inspect the descendants between the hit view and that root.
        var view: NSView? = hitView
        while let candidate = view, candidate !== scrollView.documentView {
            if candidate is NSControl ||
                candidate is NSTextView ||
                candidate is NSTableView ||
                candidate is NSCollectionView ||
                !candidate.gestureRecognizers.isEmpty {
                return false
            }
            view = candidate.superview
        }

        return true
    }

    private func startOutsideClickMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
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
