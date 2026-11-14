//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI
import ComposableArchitecture
import Aphrodite
import XcodeCleaner
import AppUninstaller
import AppKit
import Defines
import Extensions
import Screenshots
import Tailscale
import DisplayBrightness
import RadioBrowser
import Scheduler
import WebBrowser

enum SettingsItem: String, CaseIterable {
    case General = "General"
    case Customize = "Customize"
    case Tabs = "Tabs"
    case DesktopPet = "Desktop Pet"
    case Shortcuts = "Shortcuts"
    case Evolution = "Evolution"
    case Schedules = "Schedules"
    case Browser = "Browser"
    case ModelProviders = "Model Providers"
    case Aphrodite = "Aphrodite"
    case AirPods = "AirPods"
    case Radio = "Radio"
    case Authenticator = "Authenticator"
    case SystemMonitor = "System Monitor"
    case XcodeCleaner = "Xcode Cleaner"
    case AppUninstaller = "App Uninstaller"
    case Screenshots = "Screenshots"
    case Tailscale = "Tailscale"
    case PomodoroTimer = "Pomodoro Timer"
    case HideMenubarIcons = "Hide Menu Bar Icons"
    case BackNoises = "Back Noises"
    case KeepAwake = "Keep Awake"
    case DimScreen = "Dim Screen"
    case NightShift = "Night Shift"
    case KeyLight = "Key Light"
    case PrivilegedAccess = "Privileged Switch Access"
    case iOSRemote = "iOS Remote"
    case About = "About"

    /// Recently added pages that show a "New" sidebar badge until first opened.
    /// Add every new Settings page here (see AGENTS.md).
    static let newItems: Set<SettingsItem> = [.DesktopPet]

    var titleLocalizationKey: String {
        switch self {
        case .DimScreen:
            "Display"
        case .Customize:
            "Built-In"
        case .Screenshots:
            "Screenshots & Record"
        default:
            rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .General: "gearshape"
        case .Customize: "square.grid.2x2"
        case .Tabs: "rectangle.stack"
        case .DesktopPet: "pawprint"
        case .Shortcuts: "command"
        case .Evolution: "wand.and.stars"
        case .Schedules: "calendar.badge.clock"
        case .Browser: "safari"
        case .ModelProviders: "brain"
        case .Aphrodite: "sparkles"
        case .AirPods: "airpodspro"
        case .Radio: "radio"
        case .Authenticator: "lock.shield"
        case .SystemMonitor: "gauge.with.dots.needle.67percent"
        case .XcodeCleaner: "hammer"
        case .AppUninstaller: "trash"
        case .Screenshots: "camera.viewfinder"
        case .Tailscale: "network"
        case .PomodoroTimer: "timer"
        case .HideMenubarIcons: "menubar.rectangle"
        case .BackNoises: "waveform"
        case .KeepAwake: "cup.and.saucer"
        case .DimScreen: "sun.max"
        case .NightShift: "moon"
        case .KeyLight: "light.max"
        case .PrivilegedAccess: "key"
        case .iOSRemote: "iphone"
        case .About: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .General: .gray
        case .Customize: .blue
        case .Tabs: .indigo
        case .DesktopPet: .orange
        case .Shortcuts: .pink
        case .Evolution: .purple
        case .Schedules: .red
        case .Browser: .blue
        case .ModelProviders: .mint
        case .Aphrodite: .orange
        case .AirPods: .cyan
        case .Radio: .teal
        case .Authenticator: .green
        case .SystemMonitor: .blue
        case .XcodeCleaner: .brown
        case .AppUninstaller: .red
        case .Screenshots: .purple
        case .Tailscale: .indigo
        case .PomodoroTimer: .orange
        case .HideMenubarIcons: .gray
        case .BackNoises: .teal
        case .KeepAwake: .brown
        case .DimScreen: .yellow
        case .NightShift: .indigo
        case .KeyLight: .orange
        case .PrivilegedAccess: .yellow
        case .iOSRemote: .blue
        case .About: .gray
        }
    }
}

@MainActor
class SettingsVM: ObservableObject {

    static let shared = SettingsVM()

    @Published var settingItems: [SettingsItem]

    @Published var selection: SettingsItem? = .General {
        didSet {
            if let selection { seenNewItems = newBadgeTracker.markSeen(selection) }
        }
    }

    @Published private(set) var seenNewItems: Set<SettingsItem>
    private let newBadgeTracker = SettingsNewBadgeTracker()

    var evolutionStore = Store(
        initialState: EvolutionReducer.State()) {
            EvolutionReducer()
        } withDependencies: {
            $0.evolutionListService = .liveValue
        }

    /// Edits what clicking the desktop pet does; the catalog comes from the same executor schedules use.
    lazy var desktopPetStore = Store(initialState: DesktopPetSettingsFeature.State()) {
        DesktopPetSettingsFeature()
    } withDependencies: {
        $0.scheduleExecutor = .app
    }

    lazy var shortcutsStore = Store(initialState: ShortcutsSettingsReducer.State()) {
        ShortcutsSettingsReducer()
    }

    var keyLightStore = Store(
        initialState: KeyLightFeature.State()) {
            KeyLightFeature()
                ._printChanges()
        }

    var remoteAccessStore = Store(
        initialState: RemoteAccessSettingsFeature.State(
            preferences: RemoteAccessPreferencesClient.liveValue.load()
        )
    ) {
        RemoteAccessSettingsFeature()
    }

    lazy var aphroditeStore = Store(initialState: AphroditeReducer.State()) {
        AphroditeReducer()
    }

    lazy var xcodeCleanerStore = Store(initialState: XcodeCleanerFeature.State()) {
        XcodeCleanerFeature()
    }

    lazy var appUninstallerStore = Store(initialState: AppUninstallerFeature.State()) {
        AppUninstallerFeature()
    }

    let screenshotSectionRevealStore = Store(initialState: ScreenshotSectionRevealFeature.State()) {
        ScreenshotSectionRevealFeature()
    }

    /// The single session store for the Screenshots tab, shared by the popover list, OnlyControl and Settings.
    /// AppDelegate starts it at launch so captures are collected before any host appears.
    lazy var screenshotsStore = Store(initialState: ScreenshotsFeature.State()) {
        ScreenshotsFeature()
    } withDependencies: {
        $0.screenshotPresentationClient = .app
    }

    var screenshotsFolderURL: URL {
        @Dependency(\.screenshotsClient) var client
        return client.folderURL()
    }

    lazy var brightnessStore = Store(initialState: DisplayBrightnessFeature.State()) {
        DisplayBrightnessFeature()
    } withDependencies: {
        $0.displayBrightnessClient = .app
    }

    lazy var tailscaleStore = Store(initialState: TailscaleFeature.State()) {
        TailscaleFeature()
    }

    /// Keeps browse results and favorites across visits to the Radio settings page.
    lazy var radioStationsStore = Store(initialState: RadioStationsFeature.State()) {
        RadioStationsFeature()
    } withDependencies: {
        $0.radioLibraryClient = .app
    }

    /// The single session store for schedules, shared by Settings, the popover list and OnlyControl.
    /// AppDelegate starts it at launch so schedules fire whether or not any window is open.
    lazy var schedulesStore = Store(initialState: SchedulesFeature.State()) {
        SchedulesFeature()
    } withDependencies: {
        $0.scheduleExecutor = .app
        $0.scheduleNotifications = .app
        $0.scheduleSystemEvents = .app
    }

    /// The single browser store shared by Settings, the popover list and OnlyControl. Live web views belong to
    /// `BrowserWebViewPool.shared`, so pages survive tab switches and popover closes.
    lazy var browserStore = Store(initialState: BrowserFeature.State()) { BrowserFeature() }

    init() {
        seenNewItems = newBadgeTracker.seenItems()
        settingItems = SettingsItem.allCases
        if #available(macOS 26.0, *) {} else {
            if let index = settingItems.firstIndex(of: .ModelProviders) {
                settingItems.remove(at: index)
            }
        }
    }

    func showsNewBadge(_ item: SettingsItem) -> Bool {
        newBadgeTracker.showsBadge(for: item, seen: seenNewItems)
    }

    func toggleSliderbar() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .toggleSplitSettingsWindow, object: nil)
        }
    }
}

extension ScreenshotPresentationClient {
    /// App presentation for the shared Screenshots store: reveal through `StatusBarController` and the list
    /// hosts, the fly-in overlay, and the editor window (after the list host is closed so they do not overlap).
    @MainActor
    static let app = app(defaults: .standard, notificationCenter: .default)

    @MainActor
    static func app(
        defaults: UserDefaults,
        notificationCenter: NotificationCenter,
        revealStore: StoreOf<ScreenshotSectionRevealFeature>? = nil,
        appearance: @escaping @MainActor () -> SwitchListAppearance = {
            SwitchListAppearance(rawValue: Preferences.shared.currentAppearance) ?? .single
        }
    ) -> Self {
        let revealStore = revealStore ?? SettingsVM.shared.screenshotSectionRevealStore
        return Self(
            revealScreenshotsSection: {
                guard defaults.object(forKey: UserDefaults.Key.showScreenshotsTab) as? Bool ?? true else { return false }
                revealStore.send(.request(appearance() == .onlyControl ? .onlyControl : .popover))
                notificationCenter.post(name: .revealScreenshotsSection, object: nil)
                return true
            },
            flyIn: { url, target in
                await ScreenshotFlyInPresenter.shared.fly(url, to: target)
            },
            openEditor: { itemID in
                notificationCenter.post(name: .shouldHidePopover, object: nil)
                // StatusBarController hides the host on the next main-actor turn; present after it.
                Task { @MainActor in
                    await Task.yield()
                    ScreenshotEditorWindow.present(itemID: itemID) { items in
                        if let items { SettingsVM.shared.screenshotsStore.send(.itemsChanged(items)) }
                    }
                }
            },
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
    }
}

/// Keeps a section request until its host exists, including the first presentation after launch.
@Reducer
struct ScreenshotSectionRevealFeature {
    enum Host: Equatable, Sendable {
        case popover
        case onlyControl
    }

    @ObservableState
    struct State: Equatable, Sendable {
        var pendingHost: Host?
    }

    enum Action: Equatable, Sendable {
        case request(Host)
        case consumed(Host)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .request(host):
                state.pendingHost = host
            case let .consumed(host):
                if state.pendingHost == host { state.pendingHost = nil }
            }
            return .none
        }
    }
}
