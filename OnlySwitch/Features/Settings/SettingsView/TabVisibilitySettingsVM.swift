//
//  TabVisibilitySettingsVM.swift
//  OnlySwitch
//

import Authenticator
import Combine
import Defines
import Extensions
import Foundation

/// Reads and writes whether each optional popover/OnlyControl tab is shown. Authenticator and Sound Mixer
/// keep their feature `enabled` flags as the source of truth; every other tab uses its `show…Tab` default.
@MainActor
struct TabVisibilityClient {
    var isVisible: @MainActor (SectionBar.Section) -> Bool
    var setVisible: @MainActor (Bool, SectionBar.Section) -> Void

    static func defaults(
        _ defaults: UserDefaults,
        authenticatorEnabled: @escaping @MainActor () -> Bool,
        setAuthenticatorEnabled: @escaping @MainActor (Bool) -> Void,
        soundMixerEnabled: @escaping @MainActor () -> Bool,
        setSoundMixerEnabled: @escaping @MainActor (Bool) -> Void
    ) -> Self {
        Self(
            isVisible: { section in
                switch section {
                case .controls: true
                case .authenticator: authenticatorEnabled()
                case .soundMixer: soundMixerEnabled()
                default: section.visibilityDefaultsKey.map { defaults.object(forKey: $0) as? Bool ?? true } ?? true
                }
            },
            setVisible: { isVisible, section in
                switch section {
                case .controls: break
                case .authenticator: setAuthenticatorEnabled(isVisible)
                case .soundMixer: setSoundMixerEnabled(isVisible)
                default: section.visibilityDefaultsKey.map { defaults.set(isVisible, forKey: $0) }
                }
            }
        )
    }

    static let live = defaults(
        .standard,
        authenticatorEnabled: { AuthenticatorStore.shared.enabled },
        setAuthenticatorEnabled: { AuthenticatorStore.shared.enabled = $0 },
        soundMixerEnabled: { SoundMixerVM.shared.enabled },
        setSoundMixerEnabled: { SoundMixerVM.shared.enabled = $0 }
    )
}

extension SectionBar.Section {
    /// Tabs the user can show or hide; Controls is always present.
    static var manageable: [Self] { allCases.filter { $0 != .controls } }

    var visibilityDefaultsKey: String? {
        switch self {
        case .systemMonitor: UserDefaults.Key.showSystemMonitorTab
        case .codexUsage: UserDefaults.Key.showCodexUsageTab
        case .claudeUsage: UserDefaults.Key.showClaudeUsageTab
        case .aphrodite: UserDefaults.Key.showAphroditeTab
        case .xcodeCleaner: UserDefaults.Key.showXcodeCleanerTab
        case .appUninstaller: UserDefaults.Key.showAppUninstallerTab
        case .screenshots: UserDefaults.Key.showScreenshotsTab
        case .brightness: UserDefaults.Key.showBrightnessTab
        case .controls, .authenticator, .soundMixer: nil
        }
    }
}

@MainActor
final class TabVisibilitySettingsVM: ObservableObject {
    let sections = SectionBar.Section.manageable
    @Published private(set) var visibility: [SectionBar.Section: Bool] = [:]

    private let client: TabVisibilityClient
    private let notificationCenter: NotificationCenter
    private var settingsChanges: AnyCancellable?

    init(client: TabVisibilityClient = .live, notificationCenter: NotificationCenter = .default) {
        self.client = client
        self.notificationCenter = notificationCenter
        reload()
        // Keeps the page in sync when a tab changes elsewhere, e.g. Authenticator's own Enabled toggle.
        settingsChanges = notificationCenter.publisher(for: .changeSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
    }

    func isVisible(_ section: SectionBar.Section) -> Bool {
        visibility[section] ?? true
    }

    func setVisible(_ isVisible: Bool, for section: SectionBar.Section) {
        guard self.isVisible(section) != isVisible else { return }
        client.setVisible(isVisible, section)
        visibility[section] = client.isVisible(section)
        notificationCenter.post(name: .changeSettings, object: nil)
    }

    func reload() {
        let latest = Dictionary(uniqueKeysWithValues: sections.map { ($0, client.isVisible($0)) })
        if latest != visibility { visibility = latest }
    }
}
