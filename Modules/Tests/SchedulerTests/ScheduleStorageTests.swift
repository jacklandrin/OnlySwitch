#if os(macOS)
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

struct ScheduleStorageTests {
    private static let key = "schedulesKey"

    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "ScheduleStorageTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func sampleSchedules() -> [Schedule] {
        [
            Schedule(
                id: UUID(),
                name: "Morning",
                notifies: true,
                target: ScheduleTarget(controlID: RemoteControlID(kind: .shortcut, value: "Wake Up"), title: "Wake Up", behavior: .button),
                action: .run,
                trigger: .weekly(days: [.monday, .friday], hour: 8, minute: 30),
                activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastFiredAt: Date(timeIntervalSince1970: 1_700_003_600),
                lastOutcome: .failed("Boom"),
                lastRunAt: Date(timeIntervalSince1970: 1_700_003_601.123_456)
            ),
            Schedule(
                id: UUID(),
                name: "Every ten seconds",
                isActive: false,
                target: ScheduleTarget(controlID: RemoteControlID(kind: .evolution, value: UUID().uuidString), title: "Evo", behavior: .switch),
                action: .turnOff,
                trigger: .interval(value: 10, unit: .seconds),
                activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ]
    }

    @Test func missingKeyLoadsEmptyList() {
        withSuite { defaults in
            let storage = ScheduleStorageClient.userDefaults(defaults)
            #expect(storage.load() == .loaded([]))
        }
    }

    @Test func saveThenLoadRoundTrips() throws {
        try withSuite { defaults in
            let storage = ScheduleStorageClient.userDefaults(defaults)
            let schedules = sampleSchedules()
            try storage.save(schedules)
            #expect(defaults.data(forKey: Self.key) != nil)
            #expect(storage.load() == .loaded(schedules))
        }
    }

    @Test func garbageDataLoadsAsCorrupted() {
        withSuite { defaults in
            defaults.set(Data("not json".utf8), forKey: Self.key)
            let storage = ScheduleStorageClient.userDefaults(defaults)
            #expect(storage.load() == .corrupted)
            #expect(defaults.data(forKey: Self.key) == Data("not json".utf8))
        }
    }

    @Test func nonDataValueLoadsAsCorrupted() {
        withSuite { defaults in
            defaults.set("a string", forKey: Self.key)
            let storage = ScheduleStorageClient.userDefaults(defaults)
            #expect(storage.load() == .corrupted)
        }
    }
}
#endif
