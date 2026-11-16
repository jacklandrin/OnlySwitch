//
//  UpdateCheckScheduler.swift
//  OnlySwitch
//

import Extensions
import Foundation

/// Decides whether a found update should be shown to the user again.
struct UpdateReminderPolicy: Equatable, Sendable {
    struct Prompt: Equatable, Sendable {
        let build: String
        let date: Date
    }

    /// The same build is shown at most once within this interval.
    var remindInterval: TimeInterval = 24 * 60 * 60

    func shouldPrompt(build: String, lastPrompt: Prompt?, now: Date) -> Bool {
        guard let lastPrompt, lastPrompt.build == build else { return true }
        return now.timeIntervalSince(lastPrompt.date) >= remindInterval
    }
}

/// Checks for a newer build on launch and then every hour, and brings up the update
/// window when one is found.
@MainActor
final class UpdateCheckScheduler {
    static let checkInterval: Duration = .seconds(60 * 60)

    private let defaults: UserDefaults
    private let policy: UpdateReminderPolicy
    private let isEnabled: @MainActor () -> Bool
    private let probe: @MainActor () async -> UpdateProbeResult
    private let presentUpdate: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private var task: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        policy: UpdateReminderPolicy = UpdateReminderPolicy(),
        isEnabled: @escaping @MainActor () -> Bool,
        probe: @escaping @MainActor () async -> UpdateProbeResult,
        presentUpdate: @escaping @MainActor () -> Void,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.policy = policy
        self.isEnabled = isEnabled
        self.probe = probe
        self.presentUpdate = presentUpdate
        self.now = now
    }

    static func live() -> UpdateCheckScheduler {
        UpdateCheckScheduler(
            isEnabled: { PreferencesObserver.shared.preferences.checkUpdateOnLaunch },
            probe: { await Updater.shared.probeForUpdate() },
            presentUpdate: { Updater.shared.showUpdateWindow() }
        )
    }

    func start(initialDelay: Duration = .seconds(10)) {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                guard await self?.runCheck() != nil else { return }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func runCheck() async {
        guard isEnabled() else { return }
        guard case let .available(update) = await probe() else { return }
        // The preference may have been turned off while the network request was running.
        guard isEnabled() else { return }

        let currentDate = now()
        guard policy.shouldPrompt(build: update.build, lastPrompt: lastPrompt, now: currentDate) else { return }
        defaults.set(update.build, forKey: UserDefaults.Key.lastPromptedUpdateBuild)
        defaults.set(currentDate, forKey: UserDefaults.Key.lastPromptedUpdateDate)
        presentUpdate()
    }

    private var lastPrompt: UpdateReminderPolicy.Prompt? {
        guard let build = defaults.string(forKey: UserDefaults.Key.lastPromptedUpdateBuild),
              let date = defaults.object(forKey: UserDefaults.Key.lastPromptedUpdateDate) as? Date
        else { return nil }
        return UpdateReminderPolicy.Prompt(build: build, date: date)
    }
}
