//
//  ContentView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit
import ComposableArchitecture
import Defines
import Design
import Authenticator
import SwiftUI
import LaunchAtLogin
import Switches
import Utilities
import OnlyAgent
import Aphrodite
import XcodeCleaner
import AppUninstaller
import Screenshots
import DisplayBrightness
import Scheduler
import WebBrowser

enum Focusable: Hashable {
  case none
  case row(index: Int)
}

struct OnlySwitchListView: View {
    private let onPanelSizeChange: @MainActor (CGSize) -> Void
    private let onOutsideClickRetentionChanged: @MainActor (Bool) -> Void
    private let onSectionSelectionChanged: @MainActor (SectionBar.Section) -> Void
    @EnvironmentObject var switchVM:SwitchListVM
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State var distanceY:CGFloat = 0
    @State var movingIndex = -1
    @State var hoverIndex = -1
    @ObservedObject var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var authenticatorStore = AuthenticatorStore.shared
    @ObservedObject private var soundMixerVM = SoundMixerVM.shared
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    @FocusState var focusedBar: Focusable?
    @State var selectedSection: SectionBar.Section = .controls
    @State private var measuredContentHeight: CGFloat?
    @State private var measuredChromeHeight: CGFloat = 144
    @State private var maximumPanelHeight = NSScreen.main?.visibleFrame.height ?? CGFloat(700)
    @State private var presentedPanelHeight: CGFloat?
    @State private var aphroditeStore: StoreOf<AphroditeReducer>
    private let screenshotSectionRevealStore = SettingsVM.shared.screenshotSectionRevealStore
    @AppStorage(UserDefaults.Key.showClaudeUsageTab) private var showClaudeUsageTab = true
    @AppStorage(UserDefaults.Key.showCodexUsageTab) private var showCodexUsageTab = true
    @AppStorage(UserDefaults.Key.showSystemMonitorTab) private var showSystemMonitorTab = true
    @AppStorage(UserDefaults.Key.showAphroditeTab) private var showAphroditeTab = true
    @AppStorage(UserDefaults.Key.showXcodeCleanerTab) private var showXcodeCleanerTab = true
    @AppStorage(UserDefaults.Key.showAppUninstallerTab) private var showAppUninstallerTab = true
    @AppStorage(UserDefaults.Key.showScreenshotsTab) private var showScreenshotsTab = true
    @AppStorage(UserDefaults.Key.showBrightnessTab) private var showBrightnessTab = true
    @AppStorage(UserDefaults.Key.showSchedulesTab) private var showSchedulesTab = true
    @AppStorage(UserDefaults.Key.showBrowserTab) private var showBrowserTab = true
    @AppStorage(UserDefaults.Key.tabOrder) private var tabOrder = ""

    let columns = [
        GridItem(.fixed(Layout.popoverWidth - 40)),
        GridItem(.fixed(Layout.popoverWidth - 40))
    ]

    init(onPanelSizeChange: @escaping @MainActor (CGSize) -> Void = { _ in }, onOutsideClickRetentionChanged: @escaping @MainActor (Bool) -> Void = { _ in }, onSectionSelectionChanged: @escaping @MainActor (SectionBar.Section) -> Void = { _ in }) {
        self.onPanelSizeChange = onPanelSizeChange
        self.onOutsideClickRetentionChanged = onOutsideClickRetentionChanged
        self.onSectionSelectionChanged = onSectionSelectionChanged
        _aphroditeStore = State(initialValue: Store(initialState: .init()) { AphroditeReducer() })
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()
                BluredSoundWave(width: listWidth, height: soundWaveHeight)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .isHidden(
                        selectedSection != .controls || !switchVM.soundWaveEffectDisplay || !playerItem.isPlaying,
                        remove: true
                    )
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual {
                        bottomBar.opacity(0.7).padding(.top, 20)
                    }
                    if SectionBar.shouldShowBar(for: sections) {
                        SystemMonitorSectionBar(
                            sections: sections,
                            selection: $selectedSection,
                            visibleSegmentLimit: SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single
                                ? SectionBar.singleColumnVisibleSegmentLimit : nil
                        )
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: PanelChromeHeightKey.self, value: proxy.size.height) })

                ScrollView {
                    Group {
                        switch selectedSection {
                        case .controls:
                            if switchVM.currentAppearance == SwitchListAppearance.single.rawValue {
                                singleSwitchList
                            } else {
                                dualcolumnList
                            }
                        case .authenticator:
                            AuthenticatorPanelView()
                        case .soundMixer:
                            SoundMixerPanelView()
                        case .systemMonitor:
                            SystemMonitorPanelContainer()
                        case .claudeUsage:
                            if #available(macOS 14.0, *) {
                                ClaudeUsagePanelContainer(managesScrolling: false)
                            }
                        case .codexUsage:
                            if #available(macOS 14.0, *) {
                                CodexUsagePanelContainer(managesScrolling: false)
                            }
                        case .xcodeCleaner:
                            XcodeCleanerView(store: SettingsVM.shared.xcodeCleanerStore, managesScrolling: false, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .appUninstaller:
                            AppUninstallerView(store: SettingsVM.shared.appUninstallerStore, managesScrolling: false, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .brightness:
                            DisplayBrightnessView(store: SettingsVM.shared.brightnessStore, compact: true, managesScrolling: false)
                                .id(languageManager.currentLang)
                        case .screenshots:
                            ScreenshotsView(store: SettingsVM.shared.screenshotsStore, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .schedules:
                            SchedulesPanelView(store: SettingsVM.shared.schedulesStore, compact: true) {
                                SettingsVM.shared.selection = .Schedules
                                SettingsWindow.shared.show()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .environment(\.locale, Locale(identifier: languageManager.currentLang))
                            .id(languageManager.currentLang)
                        case .browser:
                            BrowserPanelView(store: SettingsVM.shared.browserStore, compact: true) {
                                SettingsVM.shared.selection = .Browser
                                SettingsWindow.shared.show()
                            }
                            .frame(height: min(BrowserLayout.popoverContentHeight, max(240, maximumPanelHeight - measuredChromeHeight)))
                            .environment(\.locale, Locale(identifier: languageManager.currentLang))
                            .id(languageManager.currentLang)
                        case .aphrodite:
                            if #available(macOS 26.0, *) {
                                AphroditePanelView(
                                    store: aphroditeStore,
                                    maximumRunningHeight: max(0, maximumPanelHeight - measuredChromeHeight)
                                )
                            }
                            else { AphroditeUnavailableView() }
                        }
                    }
                    .background(GeometryReader { proxy in Color.clear.preference(key: PanelContentHeightKey.self, value: proxy.size.height) })
                }
                .frame(height: presentedScrollHeight)
                .padding(.bottom, 15)
                .padding(.horizontal, 0)
                VStack(spacing: 8) {
                    if switchVM.showAds {
                        recommendApp.opacity(0.8)
                    }
                    if SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single {
                        bottomBar
                    } else {
                        Color.clear.frame(height: 20)
                    }
                }
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: PanelChromeHeightKey.self, value: proxy.size.height) })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPopover, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changeSettings, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSingleSwitchStatus, object: nil)) { n in
            if let type = n.object as? SwitchType {
                switchVM.refreshSingleSwitchStatus(type: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMenubarCollapse, object: nil)) { _ in
            switchVM.refreshSingleSwitchStatus(type: .hideMenubarIcons)
        }
        .onChange(of: screenshotSectionRevealStore.pendingHost) { _, _ in
            consumeScreenshotSectionReveal()
        }
        .onChange(of: sections) { _ in
            reconcileSectionSelection()
        }
        .onChange(of: selectedSection) { section in
            onSectionSelectionChanged(section)
            onOutsideClickRetentionChanged(!section.allowsOutsideClickDismissal)
        }
        .onPreferenceChange(PanelContentHeightKey.self) { measuredContentHeight = $0.isFinite && $0 >= 0 ? $0 : nil }
        .onPreferenceChange(PanelChromeHeightKey.self) { measuredChromeHeight = $0 + 15 }
        .background(PanelScreenHeightReader { maximumPanelHeight = $0 })
        .frame(width: listWidth, height: currentPanelHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelRenderedSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PanelRenderedSizeKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            onPanelSizeChange(size)
        }
        .onChange(of: adaptivePanelHeight) { updatePresentedPanelHeight(to: $0) }
        .onChange(of: accessibilityReduceMotion) { _ in
            updatePresentedPanelHeight(to: adaptivePanelHeight)
        }
        .onAppear {
            consumeScreenshotSectionReveal()
            presentedPanelHeight = adaptivePanelHeight
            onSectionSelectionChanged(selectedSection)
            onOutsideClickRetentionChanged(!selectedSection.allowsOutsideClickDismissal)
        }
    }

    private func consumeScreenshotSectionReveal() {
        guard screenshotSectionRevealStore.pendingHost == .popover else { return }
        if sections.contains(.screenshots) { selectedSection = .screenshots }
        screenshotSectionRevealStore.send(.consumed(.popover))
    }
    
    private var adaptivePanelHeight: CGFloat {
        AdaptivePanelHeightPolicy(
            minimumContentHeight: measuredContentHeight == nil ? 120 : 0,
            chromeHeight: measuredChromeHeight,
            maximumPanelHeight: maximumPanelHeight
        ).panelHeight(for: measuredContentHeight)
    }

    private var currentPanelHeight: CGFloat { presentedPanelHeight ?? adaptivePanelHeight }

    private var presentedScrollHeight: CGFloat { max(0, currentPanelHeight - measuredChromeHeight) }

    private func updatePresentedPanelHeight(to height: CGFloat) {
        if accessibilityReduceMotion {
            presentedPanelHeight = height
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                presentedPanelHeight = height
            }
        }
    }
    
    func move(from source: IndexSet, to destination: Int) {
        switchVM.moveItem(from: source, to: destination)
    }
    
    var listWidth:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40
    }
    
    var soundWaveHeight:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.soundWaveHeight : Layout.soundWaveHeight / 2
    }

    var shouldShowAuthenticatorPanel: Bool {
        authenticatorStore.enabled
    }

    var sections: [SectionBar.Section] {
        SectionBar.sections(
            authenticator: shouldShowAuthenticatorPanel,
            soundMixer: soundMixerVM.enabled,
            systemMonitor: showSystemMonitorTab,
            codexUsage: showCodexUsageTab,
            claudeUsage: showClaudeUsageTab,
            aphrodite: showAphroditeTab,
            xcodeCleaner: showXcodeCleanerTab,
            appUninstaller: showAppUninstallerTab,
            screenshots: showScreenshotsTab,
            brightness: showBrightnessTab,
            schedules: showSchedulesTab,
            browser: showBrowserTab,
            order: SectionBar.manageableOrder(from: tabOrder)
        )
    }

    func reconcileSectionSelection() {
        if !sections.contains(selectedSection) {
            selectedSection = .controls
        }
    }
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PanelChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct PanelRenderedSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        OnlySwitchListView()
            .frame(width: Layout.popoverWidth, height: Layout.popoverHeight)
            .environmentObject(SwitchListVM())
    }
}
#endif
