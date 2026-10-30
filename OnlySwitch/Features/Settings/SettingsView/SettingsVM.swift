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

enum SettingsItem: String, CaseIterable {
    case General = "General"
    case Customize = "Customize"
    case Tabs = "Tabs"
    case Shortcuts = "Shortcuts"
    case Evolution = "Evolution"
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

    var titleLocalizationKey: String {
        switch self {
        case .DimScreen:
            "Display"
        case .Customize:
            "Built-In"
        default:
            rawValue
        }
    }
}

@MainActor
class SettingsVM: ObservableObject {

    static let shared = SettingsVM()

    @Published var settingItems: [SettingsItem]

    @Published var selection: SettingsItem? = .General

    var evolutionStore = Store(
        initialState: EvolutionReducer.State()) {
            EvolutionReducer()
                ._printChanges()
        } withDependencies: {
            $0.evolutionListService = .liveValue
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

    init() {
        settingItems = SettingsItem.allCases
        if #available(macOS 26.0, *) {} else {
            if let index = settingItems.firstIndex(of: .ModelProviders) {
                settingItems.remove(at: index)
            }
        }
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
