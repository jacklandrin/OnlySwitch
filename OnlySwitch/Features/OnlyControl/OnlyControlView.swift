//
//  OnlyControlView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/8/27.
//

import AppKit
import Authenticator
import Combine
import ComposableArchitecture
import SwiftUI
import OnlyControl
import Defines
import Extensions
import Foundation
import SystemMonitor
import OnlyAgent
import Aphrodite
import Utilities

struct OnlyControlView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: StoreOf<OnlyControlReducer>
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var authenticatorStore = AuthenticatorStore.shared
    @ObservedObject private var soundMixerVM = SoundMixerVM.shared
    @State private var currentDate = Date()
    @State private var measuredContentHeight: CGFloat?
    @State private var measuredHeaderHeight: CGFloat = 36
    @State private var measuredFooterHeight: CGFloat = 36
    let onPanelHeightChange: @MainActor (CGFloat) -> Void
    @ObservedObject private var sizingContext: OnlyControlSizingContext
    @AppStorage(UserDefaults.Key.showCodexUsageTab) private var showCodexUsageTab = true
    @AppStorage(UserDefaults.Key.showSystemMonitorTab) private var showSystemMonitorTab = true
    @AppStorage(UserDefaults.Key.showAphroditeTab) private var showAphroditeTab = true
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(store: StoreOf<OnlyControlReducer>, sizingContext: OnlyControlSizingContext = .init(), onPanelHeightChange: @escaping @MainActor (CGFloat) -> Void = { _ in }) {
        self.store = store
        self.sizingContext = sizingContext
        self.onPanelHeightChange = onPanelHeightChange
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
                    if SectionBar.shouldShowBar(for: sections) {
                        OnlyControlSectionBar(
                            sections: sections,
                            selection: selectedSection
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: OnlyControlHeaderHeightKey.self, value: proxy.size.height)
                        })
                    }

                    ScrollView {
                        sectionContent
                            .background(GeometryReader { proxy in Color.clear.preference(key: OnlyControlContentHeightKey.self, value: proxy.size.height) })
                    }
                    .frame(height: contentViewportHeight)

                    if store.selectedSection != .aphrodite {
                        footer
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: OnlyControlFooterHeightKey.self, value: proxy.size.height)
                            })
                    }
                }
            }
            .cornerRadius(15)
            .blur(radius: store.blurRadius)
            .opacity(store.opacity)
            .animation(.interactiveSpring(duration: 0.5), value: store.blurRadius)
            .frame(width: 800, height: innerPanelHeight)
            .ignoresSafeArea()
            .padding(10)
            .background(PanelScreenHeightReader { sizingContext.maximumPanelHeight = $0 })
            .task {
                store.send(.availableSectionsChanged(sections))
                store.send(.task)
            }
            .onChange(of: sections) { availableSections in
                store.send(.availableSectionsChanged(availableSections))
            }
            .onPreferenceChange(OnlyControlContentHeightKey.self) { height in
                measuredContentHeight = height.isFinite && height >= 0 ? height : nil
            }
            .onPreferenceChange(OnlyControlHeaderHeightKey.self) { measuredHeaderHeight = $0 }
            .onPreferenceChange(OnlyControlFooterHeightKey.self) { measuredFooterHeight = $0 }
            .onChange(of: outerPanelHeight) { onPanelHeightChange($0) }
            .onAppear { onPanelHeightChange(outerPanelHeight) }
        }
    }

    private var outerPanelHeight: CGFloat {
        AdaptivePanelHeightPolicy(
            minimumContentHeight: measuredContentHeight == nil ? 120 : 0,
            chromeHeight: sectionBarHeight + footerHeight + 20,
            maximumPanelHeight: sizingContext.maximumPanelHeight
        ).panelHeight(for: measuredContentHeight)
    }
    private var innerPanelHeight: CGFloat { max(0, outerPanelHeight - 20) }
    private var contentViewportHeight: CGFloat { max(0, innerPanelHeight - sectionBarHeight - footerHeight) }
    private var sectionBarHeight: CGFloat { SectionBar.shouldShowBar(for: sections) ? measuredHeaderHeight : 0 }
    private var footerHeight: CGFloat { store.selectedSection == .aphrodite ? 0 : measuredFooterHeight }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.selectedSection {
            case .controls:
                controlsPage
            case .authenticator:
                authenticatorPage
            case .soundMixer:
                soundMixerPage
            case .systemMonitor:
                systemMonitorPage
            case .codexUsage:
                codexUsagePage
            case .aphrodite:
                aphroditePage
        }
    }

    private var authenticatorPage: some View {
        VStack(spacing: 0) {
            AuthenticatorPanelView(initiallyExpanded: true).padding(.vertical, 8)
        }
    }

    private var soundMixerPage: some View {
        VStack(spacing: 0) {
            SoundMixerPanelView(initiallyExpanded: true).padding(.vertical, 8)
        }
    }

    private var controlsPage: some View {
        VStack(spacing: 0) {
            controlHeader
                .padding(.horizontal, 30)
                .padding(.top, 12)

            DashboardView(store: store.scope(state: \.dashboard, action: \.dashboardAction), managesScrolling: false)
        }
    }

    private var systemMonitorPage: some View {
        VStack(spacing: 0) {
            SystemMonitorPanelView(store: store.scope(state: \.systemMonitor, action: \.systemMonitor))
        }
    }

    private var codexUsagePage: some View {
        VStack(spacing: 0) {
            if #available(macOS 14.0, *) {
                CodexUsagePanelContainer(managesScrolling: false)
            }
        }
    }

    private var aphroditePage: some View {
        Group { if #available(macOS 26.0, *) { AphroditePanelView() } else { AphroditeUnavailableView() } }
    }

    private var controlHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 16) {
                Text(currentDate, style: .time)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .layoutPriority(1)
                    .onReceive(timer) { _ in
                        currentDate = Date()
                    }

                Spacer(minLength: 16)

                TimerCountDownView(ptswitch: PomodoroTimerSwitch.shared, showImage: true)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.bottom, 8)
            }

            if store.isAirPodsConnected && !store.airPodsBatteryValues.isEmpty {
                AirPodsBatteryView(batteryValues: store.airPodsBatteryValues)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("AirPods battery levels".localized())
            }
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

    private var sections: [SectionBar.Section] {
        SectionBar.sections(
            authenticator: authenticatorStore.enabled,
            soundMixer: soundMixerVM.enabled,
            systemMonitor: showSystemMonitorTab,
            codexUsage: showCodexUsageTab,
            aphrodite: showAphroditeTab
        )
    }
}

private struct OnlyControlContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OnlyControlHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OnlyControlFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor
final class OnlyControlSizingContext: ObservableObject {
    @Published var maximumPanelHeight: CGFloat
    init(maximumPanelHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 620) { self.maximumPanelHeight = maximumPanelHeight }
}

private struct OnlyControlSectionBar: View {
    let sections: [SectionBar.Section]
    @Binding var selection: SectionBar.Section
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        tabButtons
            .padding(2)
            .background(.black.opacity(0.08), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Only Control sections".localized())
    }

    private var tabButtons: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let spacingWidth = spacing * CGFloat(max(0, sections.count - 1))
            let segmentWidth = max(0, (proxy.size.width - spacingWidth) / CGFloat(max(1, sections.count)))
            let selectedIndex = sections.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                selectionIndicator
                    .frame(width: segmentWidth, height: 20)
                    .offset(x: CGFloat(selectedIndex) * (segmentWidth + spacing))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(spacing: spacing) {
                    ForEach(sections, id: \.self) { section in
                        sectionButton(section)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
        }
        .frame(height: 20)
    }

    private func sectionButton(_ section: SectionBar.Section) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.32)
            withAnimation(animation) {
                selection = section
            }
        } label: {
            Label(section.title, systemImage: section.symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(selection == section ? selectedForegroundStyle : .secondary)
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityHint("Shows the %@ section".localizeWithFormat(arguments: section.title))
        .help(Text(section.title))
    }

    private var selectedForegroundStyle: Color {
        colorScheme == .dark ? .white : .primary
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.16)), in: Capsule())
        } else {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
        }
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

    private static let initialContentSize = NSSize(width: 820, height: 220)
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
    private var lastProposedHeight: CGFloat = 220
    private let sizingContext = OnlyControlSizingContext()

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
        let view = OnlyControlHostingView(rootView: OnlyControlView(store: onlyControlStore, sizingContext: sizingContext) { [weak self] height in self?.setAdaptiveContentHeight(height) })
        setContentSize(Self.initialContentSize)
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
        setAdaptiveContentHeight(lastProposedHeight)
    }

    private var screenContainingWindow: NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
    }

    private func setAdaptiveContentHeight(_ proposedHeight: CGFloat) {
        lastProposedHeight = proposedHeight
        guard proposedHeight.isFinite, let screen = screen ?? screenContainingWindow ?? NSScreen.main else { return }
        if sizingContext.maximumPanelHeight != screen.visibleFrame.height {
            sizingContext.maximumPanelHeight = screen.visibleFrame.height
        }
        let height = min(max(1, proposedHeight), screen.visibleFrame.height)
        var next = frame
        next.origin.y += next.height - height
        next.size = NSSize(width: 820, height: height)
        next.origin.y = max(screen.visibleFrame.minY, min(next.origin.y, screen.visibleFrame.maxY - height))
        next = constrainFrameRect(next, to: screen)
        guard next != frame else { return }
        setFrame(next, display: true, animate: false)
    }

    func windowDidChangeScreen(_ notification: Notification) { setAdaptiveContentHeight(lastProposedHeight) }
    func windowDidChangeScreenProfile(_ notification: Notification) { setAdaptiveContentHeight(lastProposedHeight) }

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
