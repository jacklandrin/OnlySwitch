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
/// The order of the optional tabs is stored in `UserDefaults.Key.tabOrder`.
@MainActor
struct TabVisibilityClient {
    var isVisible: @MainActor (SectionBar.Section) -> Bool
    var setVisible: @MainActor (Bool, SectionBar.Section) -> Void
    var order: @MainActor () -> [SectionBar.Section] = { SectionBar.Section.manageable }
    var setOrder: @MainActor ([SectionBar.Section]) -> Void = { _ in }

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
            },
            order: { SectionBar.manageableOrder(from: defaults.string(forKey: UserDefaults.Key.tabOrder) ?? "") },
            setOrder: { defaults.set(SectionBar.storedOrder($0), forKey: UserDefaults.Key.tabOrder) }
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
        case .schedules: UserDefaults.Key.showSchedulesTab
        case .controls, .authenticator, .soundMixer: nil
        }
    }
}

@MainActor
final class TabVisibilitySettingsVM: ObservableObject {
    @Published private(set) var sections: [SectionBar.Section] = SectionBar.Section.manageable
    @Published private(set) var visibility: [SectionBar.Section: Bool] = [:]
    /// While true the rows show drag handles instead of visibility toggles.
    @Published private(set) var isReordering = false

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

    func toggleReordering() {
        isReordering.toggle()
    }

    /// Moves `section` into `target`'s position; used while a row is dragged over another.
    func move(_ section: SectionBar.Section, onto target: SectionBar.Section) {
        guard let from = sections.firstIndex(of: section), let to = sections.firstIndex(of: target), from != to else { return }
        move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }

    func canMove(_ section: SectionBar.Section, by offset: Int) -> Bool {
        sections.firstIndex(of: section).map { sections.indices.contains($0 + offset) } ?? false
    }

    /// Moves a tab one or more places up (negative offset) or down; used by the row's context menu.
    func move(_ section: SectionBar.Section, by offset: Int) {
        guard canMove(section, by: offset), let index = sections.firstIndex(of: section) else { return }
        move(section, onto: sections[index + offset])
    }

    /// Same semantics as SwiftUI's `onMove`: `destination` is the index before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter(sections.indices.contains).map { sections[$0] }
        var reordered = sections.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = min(max(0, destination - source.filter { $0 < destination }.count), reordered.count)
        reordered.insert(contentsOf: moving, at: insertion)
        guard reordered != sections else { return }
        client.setOrder(reordered)
        sections = client.order()
        notificationCenter.post(name: .changeSettings, object: nil)
    }

    func reload() {
        let latestOrder = client.order()
        if latestOrder != sections { sections = latestOrder }
        let latest = Dictionary(uniqueKeysWithValues: sections.map { ($0, client.isVisible($0)) })
        if latest != visibility { visibility = latest }
    }
}
