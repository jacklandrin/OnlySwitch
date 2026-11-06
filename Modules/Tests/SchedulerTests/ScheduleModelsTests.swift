#if os(macOS)
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

struct ScheduleModelsTests {
    @Test func buttonsOnlyAllowRun() {
        #expect(ScheduleAction.allowed(for: .button) == [.run])
    }

    @Test(arguments: [RemoteControlDescriptor.Behavior.switch, .player])
    func switchesAndPlayersAllowTurnOnOffAndToggle(behavior: RemoteControlDescriptor.Behavior) {
        #expect(ScheduleAction.allowed(for: behavior) == [.turnOn, .turnOff, .toggle])
    }

    @Test func actionsMapToRemoteActions() {
        #expect(ScheduleAction.turnOn.remoteAction() == .setState(true))
        #expect(ScheduleAction.turnOff.remoteAction() == .setState(false))
        #expect(ScheduleAction.run.remoteAction() == .trigger)
    }

    @Test func toggleInvertsTheCurrentState() {
        #expect(ScheduleAction.toggle.remoteAction(currentlyOn: true) == .setState(false))
        #expect(ScheduleAction.toggle.remoteAction(currentlyOn: false) == .setState(true))
        #expect(ScheduleAction.toggle.remoteAction(currentlyOn: nil) == nil)
    }

    @Test func onlyToggleNeedsTheCurrentState() {
        #expect(ScheduleAction.allCases.filter(\.needsCurrentState) == [.toggle])
    }

    @Test func toggleSurvivesARoundTrip() throws {
        let data = try JSONEncoder().encode(ScheduleAction.toggle)
        #expect(try JSONDecoder().decode(ScheduleAction.self, from: data) == .toggle)
    }

    @Test func weekdayRawValuesMatchCalendarNumbering() {
        #expect(ScheduleWeekday.sunday.rawValue == 1)
        #expect(ScheduleWeekday.monday.rawValue == 2)
        #expect(ScheduleWeekday.saturday.rawValue == 7)
    }

    @Test(arguments: [
        ScheduleTrigger.interval(value: 90, unit: .seconds),
        .interval(value: 5, unit: .minutes),
        .interval(value: 2, unit: .hours),
        .hourly(minute: 15),
        .weekly(days: [], hour: 8, minute: 30),
        .weekly(days: ScheduleWeekday.weekdays, hour: 23, minute: 59)
    ])
    func scheduleRoundTripsThroughJSON(trigger: ScheduleTrigger) throws {
        let schedule = Schedule(
            id: UUID(),
            name: "Dark mode",
            notifies: true,
            target: ScheduleTarget(
                controlID: RemoteControlID(kind: .builtIn, value: "darkMode"),
                title: "Dark Mode",
                behavior: .switch
            ),
            action: .turnOn,
            trigger: trigger,
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastFiredAt: Date(timeIntervalSince1970: 1_700_000_600),
            lastOutcome: .failed("Boom"),
            lastRunAt: Date(timeIntervalSince1970: 1_700_000_601)
        )
        let data = try JSONEncoder().encode(schedule)
        #expect(try JSONDecoder().decode(Schedule.self, from: data) == schedule)
    }

    @Test func initDefaults() {
        let schedule = Schedule(
            id: UUID(),
            name: "Run",
            target: ScheduleTarget(
                controlID: RemoteControlID(kind: .shortcut, value: "Backup"),
                title: "Backup",
                behavior: .button
            ),
            action: .run,
            trigger: .hourly(minute: 0),
            activatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(schedule.isActive)
        #expect(!schedule.notifies)
        #expect(schedule.lastFiredAt == nil)
        #expect(schedule.lastOutcome == nil)
        #expect(schedule.lastRunAt == nil)
    }

    @Test func intervalUnitSeconds() {
        #expect(ScheduleIntervalUnit.seconds.seconds == 1)
        #expect(ScheduleIntervalUnit.minutes.seconds == 60)
        #expect(ScheduleIntervalUnit.hours.seconds == 3600)
    }
}
#endif
