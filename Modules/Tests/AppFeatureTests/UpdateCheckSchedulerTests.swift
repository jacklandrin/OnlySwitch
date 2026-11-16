//
//  UpdateCheckSchedulerTests.swift
//  OnlySwitchTests
//

import Extensions
import Foundation
import Testing
@testable import AppFeature

struct UpdateReminderPolicyTests {
    private let policy = UpdateReminderPolicy()
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Prompts when nothing was shown before")
    func promptsWithoutHistory() {
        #expect(policy.shouldPrompt(build: "314", lastPrompt: nil, now: start))
    }

    @Test("Prompts immediately for a different build")
    func promptsForNewBuild() {
        let last = UpdateReminderPolicy.Prompt(build: "312", date: start)
        #expect(policy.shouldPrompt(build: "314", lastPrompt: last, now: start.addingTimeInterval(60)))
    }

    @Test("Waits 24 hours before showing the same build again")
    func throttlesSameBuild() {
        let last = UpdateReminderPolicy.Prompt(build: "314", date: start)
        #expect(!policy.shouldPrompt(build: "314", lastPrompt: last, now: start.addingTimeInterval(60 * 60)))
        #expect(!policy.shouldPrompt(build: "314", lastPrompt: last, now: start.addingTimeInterval(24 * 60 * 60 - 1)))
        #expect(policy.shouldPrompt(build: "314", lastPrompt: last, now: start.addingTimeInterval(24 * 60 * 60)))
    }
}

@MainActor
struct UpdateCheckSchedulerTests {
    @MainActor
    private final class Harness {
        let defaults: UserDefaults
        var enabled = true
        var result: UpdateProbeResult = .upToDate
        var probeCount = 0
        var presentCount = 0
        var now = Date(timeIntervalSince1970: 1_000_000)

        init() {
            let suite = "UpdateCheckSchedulerTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
        }

        func makeScheduler() -> UpdateCheckScheduler {
            UpdateCheckScheduler(
                defaults: defaults,
                isEnabled: { self.enabled },
                probe: {
                    self.probeCount += 1
                    return self.result
                },
                presentUpdate: { self.presentCount += 1 },
                now: { self.now }
            )
        }
    }

    private let update = AvailableUpdate(build: "314", displayVersion: "3.6.0")

    @Test("Shows the update window when a newer build is found")
    func presentsNewBuild() async {
        let harness = Harness()
        harness.result = .available(update)
        await harness.makeScheduler().runCheck()

        #expect(harness.presentCount == 1)
        #expect(harness.defaults.string(forKey: UserDefaults.Key.lastPromptedUpdateBuild) == "314")
    }

    @Test("Does not check when automatic update checks are disabled")
    func skipsWhenDisabled() async {
        let harness = Harness()
        harness.enabled = false
        harness.result = .available(update)
        await harness.makeScheduler().runCheck()

        #expect(harness.probeCount == 0)
        #expect(harness.presentCount == 0)
    }

    @Test("Does nothing when the app is up to date, busy, or the check fails", arguments: [
        UpdateProbeResult.upToDate, .busy, .failed
    ])
    func ignoresNonUpdateResults(result: UpdateProbeResult) async {
        let harness = Harness()
        harness.result = result
        await harness.makeScheduler().runCheck()

        #expect(harness.probeCount == 1)
        #expect(harness.presentCount == 0)
    }

    @Test("Hourly checks show the same build at most once a day")
    func throttlesHourlyChecks() async {
        let harness = Harness()
        harness.result = .available(update)
        let scheduler = harness.makeScheduler()

        await scheduler.runCheck()
        harness.now.addTimeInterval(60 * 60)
        await scheduler.runCheck()
        #expect(harness.presentCount == 1)

        harness.now.addTimeInterval(23 * 60 * 60)
        await scheduler.runCheck()
        #expect(harness.presentCount == 2)
    }

    @Test("A newer build is shown right away even after a recent prompt")
    func presentsNewerBuildImmediately() async {
        let harness = Harness()
        harness.result = .available(update)
        let scheduler = harness.makeScheduler()

        await scheduler.runCheck()
        harness.now.addTimeInterval(60 * 60)
        harness.result = .available(AvailableUpdate(build: "315", displayVersion: "3.6.1"))
        await scheduler.runCheck()

        #expect(harness.presentCount == 2)
    }

    @Test("Display text includes the build number")
    func displayText() {
        #expect(update.displayText == "3.6.0 (314)")
        #expect(AvailableUpdate(build: "314", displayVersion: "314").displayText == "314")
    }
}
