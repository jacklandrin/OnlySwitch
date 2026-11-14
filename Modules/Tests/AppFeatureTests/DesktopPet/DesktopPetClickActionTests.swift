import Extensions
import Foundation
import RemoteCore
import Scheduler
import Testing
@testable import AppFeature

@MainActor
struct DesktopPetClickActionTests {
    let target = ScheduleTarget(
        controlID: RemoteControlID(kind: .builtIn, value: "darkMode"),
        title: "Dark Mode",
        behavior: .switch
    )

    @Test func buttonsRunAndEverythingElseToggles() {
        #expect(DesktopPetClickAction.runAction(for: .button) == .run)
        #expect(DesktopPetClickAction.runAction(for: .switch) == .toggle)
        #expect(DesktopPetClickAction.runAction(for: .player) == .toggle)
    }

    @Test func storageDefaultsToOnlyControlAndRoundTrips() throws {
        let suite = "DesktopPetClickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = DesktopPetClickActionStorage.userDefaults(defaults)

        #expect(storage.load() == .onlyControl)
        storage.save(.control(target))
        #expect(storage.load() == .control(target))
        storage.save(.onlyControl)
        #expect(storage.load() == .onlyControl)
    }

    @Test func corruptedStorageFallsBackToOnlyControl() throws {
        let suite = "DesktopPetClickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: UserDefaults.Key.desktopPetClickAction)

        #expect(DesktopPetClickActionStorage.userDefaults(defaults).load() == .onlyControl)
    }

    @Test func clickActionIsIncludedInSettingsBackup() {
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.desktopPetClickAction))
    }

    @Test func onlyControlActionShowsOnlyControl() async {
        var shown = 0
        let performer = DesktopPetClickPerformer(
            load: { .onlyControl },
            run: { _, _ in
                Issue.record("OnlyControl action must not run a control")
                return .succeeded
            },
            showOnlyControl: { shown += 1 }
        )

        await performer.perform()

        #expect(shown == 1)
    }

    @Test func controlActionRunsTargetWithMappedAction() async {
        var runs: [(RemoteControlID, ScheduleAction)] = []
        var shown = 0
        let target = target
        let performer = DesktopPetClickPerformer(
            load: { .control(target) },
            run: { id, action in
                runs.append((id, action))
                return .succeeded
            },
            showOnlyControl: { shown += 1 }
        )

        await performer.perform()

        #expect(runs.map(\.0) == [target.controlID])
        #expect(runs.map(\.1) == [.toggle])
        #expect(shown == 0)
    }

    @Test func failedRunFallsBackToOnlyControl() async {
        var shown = 0
        let target = target
        let performer = DesktopPetClickPerformer(
            load: { .control(target) },
            run: { _, _ in .failed("Unknown control") },
            showOnlyControl: { shown += 1 }
        )

        await performer.perform()

        #expect(shown == 1)
    }
}
