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
import Design
import Extensions
import Foundation
import SystemMonitor
import OnlyAgent
import Aphrodite
import XcodeCleaner
import AppUninstaller
import Screenshots
import DisplayBrightness
import Scheduler
import Utilities

struct OnlyControlView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: StoreOf<OnlyControlReducer>
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var authenticatorStore = AuthenticatorStore.shared
    @ObservedObject private var soundMixerVM = SoundMixerVM.shared
    @State private var currentDate = Date()
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    @State private var aphroditeStore: StoreOf<AphroditeReducer>
    private let screenshotSectionRevealStore = SettingsVM.shared.screenshotSectionRevealStore
    @State private var sectionViewportHeight: CGFloat?
    @AppStorage(UserDefaults.Key.showClaudeUsageTab) private var showClaudeUsageTab = true
    @AppStorage(UserDefaults.Key.showCodexUsageTab) private var showCodexUsageTab = true
    @AppStorage(UserDefaults.Key.showSystemMonitorTab) private var showSystemMonitorTab = true
    @AppStorage(UserDefaults.Key.showAphroditeTab) private var showAphroditeTab = true
    @AppStorage(UserDefaults.Key.showXcodeCleanerTab) private var showXcodeCleanerTab = true
    @AppStorage(UserDefaults.Key.showAppUninstallerTab) private var showAppUninstallerTab = true
    @AppStorage(UserDefaults.Key.showScreenshotsTab) private var showScreenshotsTab = true
    @AppStorage(UserDefaults.Key.showBrightnessTab) private var showBrightnessTab = true
    @AppStorage(UserDefaults.Key.showSchedulesTab) private var showSchedulesTab = true
    @AppStorage(UserDefaults.Key.tabOrder) private var tabOrder = ""
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(store: StoreOf<OnlyControlReducer>) {
        self.store = store
        _aphroditeStore = State(initialValue: Store(initialState: .init()) { AphroditeReducer() })
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
                    }

                    ScrollView {
                        sectionContent
                    }
                    .frame(maxHeight: .infinity)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: OnlyControlSectionViewportHeightKey.self, value: proxy.size.height)
                    })

                    if store.selectedSection != .aphrodite {
                        footer
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                store.send(.availableSectionsChanged(sections))
                store.send(.task)
            }
            .onChange(of: sections) { availableSections in
                store.send(.availableSectionsChanged(availableSections))
            }
            .onAppear(perform: consumeScreenshotSectionReveal)
            .onChange(of: screenshotSectionRevealStore.pendingHost) { _, _ in
                consumeScreenshotSectionReveal()
            }
            .onPreferenceChange(OnlyControlSectionViewportHeightKey.self) { height in
                sectionViewportHeight = height.isFinite && height > 0 ? height : nil
            }
        }
    }

    private func consumeScreenshotSectionReveal() {
        guard screenshotSectionRevealStore.pendingHost == .onlyControl else { return }
        if sections.contains(.screenshots) { store.send(.selectedSectionChanged(.screenshots)) }
        screenshotSectionRevealStore.send(.consumed(.onlyControl))
    }

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
            case .claudeUsage:
                claudeUsagePage
            case .codexUsage:
                codexUsagePage
            case .xcodeCleaner:
                XcodeCleanerView(store: SettingsVM.shared.xcodeCleanerStore, managesScrolling: false)
                    .id(languageManager.currentLang)
            case .appUninstaller:
                AppUninstallerView(store: SettingsVM.shared.appUninstallerStore, managesScrolling: false)
                    .id(languageManager.currentLang)
            case .brightness:
                DisplayBrightnessView(store: SettingsVM.shared.brightnessStore, managesScrolling: false)
                    .id(languageManager.currentLang)
            case .screenshots:
                ScreenshotsView(store: SettingsVM.shared.screenshotsStore)
                    .id(languageManager.currentLang)
            case .schedules:
                SchedulesPanelView(store: SettingsVM.shared.schedulesStore, compact: false) {
                    SettingsVM.shared.selection = .Schedules
                    SettingsWindow.shared.show()
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .environment(\.locale, Locale(identifier: languageManager.currentLang))
                .id(languageManager.currentLang)
            case .aphrodite:
                aphroditePage
        }
    }

    private var authenticatorPage: some View {
        VStack(spacing: 0) {
            AuthenticatorPanelView().padding(.vertical, 8)
        }
    }

    private var soundMixerPage: some View {
        VStack(spacing: 0) {
            SoundMixerPanelView().padding(.vertical, 8)
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

    private var claudeUsagePage: some View {
        VStack(spacing: 0) {
            if #available(macOS 14.0, *) {
                ClaudeUsagePanelContainer(managesScrolling: false)
            }
        }
    }

    private var aphroditePage: some View {
        Group {
            if #available(macOS 26.0, *) {
                AphroditePanelView(store: aphroditeStore, maximumRunningHeight: sectionViewportHeight)
            } else {
                AphroditeUnavailableView()
            }
        }
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
            claudeUsage: showClaudeUsageTab,
            aphrodite: showAphroditeTab,
            xcodeCleaner: showXcodeCleanerTab,
            appUninstaller: showAppUninstallerTab,
            screenshots: showScreenshotsTab,
            brightness: showBrightnessTab,
            schedules: showSchedulesTab,
            order: SectionBar.manageableOrder(from: tabOrder)
        )
    }
}

#Preview {
    OnlyControlView(store: .init(initialState: .init()) {
        OnlyControlReducer()
    })
}

private struct OnlyControlSectionViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
