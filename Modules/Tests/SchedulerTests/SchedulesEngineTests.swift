#if os(macOS)
import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

@MainActor
struct SchedulesEngineTests {
    let now = ScheduleFixtures.date(2026, 11, 4, 12, 0)

    @Test func launchFiresAMissedHourlyScheduleOnce() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .hourly(minute: 0),
            activatedAt: now.addingTimeInterval(-5 * 3600),
            lastFiredAt: now.addingTimeInterval(-3 * 3600)
        )
        let harness = ScheduleEngineHarness(now: now, stored: .loaded([schedule]))
        let store = harness.makeStore()

        await store.send(.task) {
            $0.hasLoaded = true
            $0.schedules = [schedule]
        }
        await store.receive(\.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = now
            $0.running = [schedule.id]
        }
        await store.receive(\.refreshCatalog)
        await store.receive(\.catalogLoaded)
        await store.receive(.runFinished(schedule.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = now
        }
        await store.skipInFlightEffects()

        #expect(harness.runs.value == [RecordedRun(controlID: .builtIn("darkMode"), action: .turnOn)])
        #expect(harness.saves.value.first?.first?.lastFiredAt == now)
        #expect(harness.saves.value.last == Array(store.state.schedules))
    }

    @Test func taskOnlyLoadsOnce() async {
        var state = SchedulesFeature.State()
        state.hasLoaded = true
        let store = ScheduleEngineHarness(now: now).makeStore(state)
        await store.send(.task)
    }

    @Test func inactiveScheduleNeverRunsAndActivatingDoesNotFireImmediately() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            isActive: false,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-3600)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.tick)
        #expect(harness.saves.value.isEmpty)

        await store.send(.setActive(schedule.id, true)) {
            $0.schedules[id: schedule.id]?.isActive = true
            $0.schedules[id: schedule.id]?.activatedAt = now
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.runs.value.isEmpty)
        #expect(harness.saves.value.count == 1)
        #expect(harness.saves.value.last?.first?.isActive == true)
    }

    @Test func deactivatingPersistsAndStopsFiring() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-60)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.setActive(schedule.id, false)) {
            $0.schedules[id: schedule.id]?.isActive = false
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.runs.value.isEmpty)
        #expect(harness.saves.value.last?.first?.isActive == false)
    }

    @Test func intervalScheduleFiresAgainWhenTheTimerElapses() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-10)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = now
            $0.running = [schedule.id]
        }
        await store.receive(.runFinished(schedule.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = now
        }

        let later = now.addingTimeInterval(10)
        harness.advanceDate(by: 10)
        await harness.clock.advance(by: .seconds(10))
        await store.receive(\.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = later
            $0.running = [schedule.id]
        }
        await store.receive(.runFinished(schedule.id, .succeeded, at: later)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastRunAt = later
        }
        await store.skipInFlightEffects()

        #expect(harness.runs.value.count == 2)
    }

    @Test func aDueFireIsSkippedWhileThePreviousRunIsStillRunning() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-10)
        )
        let gate = AsyncStream<Void>.makeStream()
        let harness = ScheduleEngineHarness(now: now, gate: gate.stream)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = now
            $0.running = [schedule.id]
        }

        let later = now.addingTimeInterval(10)
        harness.advanceDate(by: 10)
        await harness.clock.advance(by: .seconds(10))
        await store.receive(\.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = later
        }
        #expect(harness.runs.value.count == 1)

        gate.continuation.yield()
        await store.receive(.runFinished(schedule.id, .succeeded, at: later)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = later
        }
        await store.skipInFlightEffects()

        #expect(harness.runs.value.count == 1)
        #expect(harness.saves.value.count == 3)
    }

    @Test func everyDueScheduleFiresOnceInPendingDateOrder() async {
        let first = ScheduleFixtures.schedule(
            1,
            controlID: .shortcut("Focus"),
            action: .run,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-10)
        )
        // Pending since 11:00, so it comes due before `first` (pending since 12:00).
        let second = ScheduleFixtures.schedule(
            2,
            trigger: .hourly(minute: 0),
            activatedAt: now.addingTimeInterval(-7200)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([first, second]))

        await store.send(.tick) {
            $0.schedules[id: first.id]?.lastFiredAt = now
            $0.schedules[id: second.id]?.lastFiredAt = now
            $0.running = [first.id, second.id]
        }
        await store.receive(.runFinished(second.id, .succeeded, at: now)) {
            $0.running = [first.id]
            $0.schedules[id: second.id]?.lastOutcome = .succeeded
            $0.schedules[id: second.id]?.lastRunAt = now
        }
        await store.receive(.runFinished(first.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: first.id]?.lastOutcome = .succeeded
            $0.schedules[id: first.id]?.lastRunAt = now
        }
        await store.skipInFlightEffects()

        #expect(harness.runs.value == [
            RecordedRun(controlID: .builtIn("darkMode"), action: .turnOn),
            RecordedRun(controlID: .shortcut("Focus"), action: .run),
        ])
    }

    @Test func runFinishedRecordsTheOutcomeAndNotifiesOnlyWhenEnabled() async {
        let failing = ScheduleFixtures.schedule(1, name: "Night", notifies: true, trigger: .hourly(minute: 0), activatedAt: now)
        let quiet = ScheduleFixtures.schedule(2, trigger: .hourly(minute: 0), activatedAt: now)
        let succeeding = ScheduleFixtures.schedule(3, name: "Morning", notifies: true, trigger: .hourly(minute: 0), activatedAt: now)
        var state = SchedulesFeature.State.loaded([failing, quiet, succeeding])
        state.running = [failing.id, quiet.id, succeeding.id]
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.runFinished(failing.id, .failed("Boom"), at: now)) {
            $0.running = [quiet.id, succeeding.id]
            $0.schedules[id: failing.id]?.lastOutcome = .failed("Boom")
            $0.schedules[id: failing.id]?.lastRunAt = now
        }
        await store.send(.runFinished(quiet.id, .succeeded, at: now)) {
            $0.running = [succeeding.id]
            $0.schedules[id: quiet.id]?.lastOutcome = .succeeded
            $0.schedules[id: quiet.id]?.lastRunAt = now
        }
        await store.send(.runFinished(succeeding.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: succeeding.id]?.lastOutcome = .succeeded
            $0.schedules[id: succeeding.id]?.lastRunAt = now
        }
        await store.finish()

        #expect(harness.notifications.value == [
            PostedNotification(
                title: String(format: ScheduleStrings.text("Schedule Notification Failed %@"), "Night"),
                body: ScheduleFormatter.outcomeSummary(.failed("Boom"))
            ),
            PostedNotification(
                title: String(format: ScheduleStrings.text("Schedule Notification Ran %@"), "Morning"),
                body: ScheduleFormatter.outcomeSummary(.succeeded)
            ),
        ])
        #expect(harness.saves.value.count == 3)
        #expect(harness.saves.value.last == Array(store.state.schedules))
    }

    @Test func runFinishedForADeletedScheduleIsIgnored() async {
        let deletedID = ScheduleFixtures.id(9)
        var state = SchedulesFeature.State.loaded([])
        state.running = [deletedID]
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.runFinished(deletedID, .succeeded, at: now)) {
            $0.running = []
        }
        await store.finish()

        #expect(harness.saves.value.isEmpty)
        #expect(harness.notifications.value.isEmpty)
    }

    @Test func runNowRunsWithoutChangingTheFireAnchor() async {
        let schedule = ScheduleFixtures.schedule(1, trigger: .hourly(minute: 0), activatedAt: now)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.runNow(schedule.id)) {
            $0.running = [schedule.id]
        }
        await store.receive(.runFinished(schedule.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = now
        }
        await store.finish()

        #expect(store.state.schedules[id: schedule.id]?.lastFiredAt == nil)
        #expect(harness.runs.value.count == 1)
    }

    @Test func runNowIsIgnoredWhileRunning() async {
        let schedule = ScheduleFixtures.schedule(1, trigger: .hourly(minute: 0), activatedAt: now)
        var state = SchedulesFeature.State.loaded([schedule])
        state.running = [schedule.id]
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.runNow(schedule.id))
        #expect(harness.runs.value.isEmpty)
    }

    @Test func systemEventAfterSleepFiresAMissedWeeklyScheduleOnce() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .weekly(days: [], hour: 9, minute: 0),
            activatedAt: now.addingTimeInterval(-3600)
        )
        let harness = ScheduleEngineHarness(now: now, stored: .loaded([schedule]))
        let store = harness.makeStore()

        await store.send(.task) {
            $0.hasLoaded = true
            $0.schedules = [schedule]
        }
        await store.receive(\.tick)
        await store.receive(\.refreshCatalog)
        await store.receive(\.catalogLoaded)

        let wake = now.addingTimeInterval(2 * 86_400)
        harness.advanceDate(by: 2 * 86_400)
        harness.events.continuation.yield()
        await store.receive(\.systemEvent)
        await store.receive(\.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = wake
            $0.running = [schedule.id]
        }
        await store.receive(\.refreshCatalog)
        await store.receive(\.catalogLoaded)
        await store.receive(.runFinished(schedule.id, .succeeded, at: wake)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = wake
        }
        harness.events.continuation.finish()
        await store.skipInFlightEffects()

        #expect(harness.runs.value.count == 1)
    }

    @Test func corruptedStorageLoadsEmptyAndIsNeverOverwritten() async {
        let harness = ScheduleEngineHarness(now: now, stored: .corrupted)
        let store = harness.makeStore()

        await store.send(.task) {
            $0.hasLoaded = true
            $0.isStorageCorrupted = true
        }
        await store.receive(\.tick)
        await store.receive(\.refreshCatalog)
        await store.receive(\.catalogLoaded)
        await store.skipInFlightEffects()

        #expect(harness.saves.value.isEmpty)
    }

    @Test func firingWhileStorageIsCorruptedDoesNotSave() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-10)
        )
        var state = SchedulesFeature.State.loaded([schedule])
        state.isStorageCorrupted = true
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.tick) {
            $0.schedules[id: schedule.id]?.lastFiredAt = now
            $0.running = [schedule.id]
        }
        await store.receive(.runFinished(schedule.id, .succeeded, at: now)) {
            $0.running = []
            $0.schedules[id: schedule.id]?.lastOutcome = .succeeded
            $0.schedules[id: schedule.id]?.lastRunAt = now
        }
        await store.skipInFlightEffects()

        #expect(harness.runs.value.count == 1)
        #expect(harness.saves.value.isEmpty)
    }

    @Test func aFailedSaveIsReported() async {
        let schedule = ScheduleFixtures.schedule(1, isActive: false, trigger: .hourly(minute: 0), activatedAt: now)
        let harness = ScheduleEngineHarness(now: now, failSaves: true)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.setActive(schedule.id, true)) {
            $0.schedules[id: schedule.id]?.isActive = true
        }
        await store.receive(\.tick)
        await store.receive(.saveFailed("Disk full")) {
            $0.saveError = "Disk full"
        }
        await store.skipInFlightEffects()
    }

    @Test func timerSleepsSixtySecondsWhenNothingIsActive() async {
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([]))

        await store.send(.tick)
        await harness.clock.advance(by: .seconds(59))
        await harness.clock.advance(by: .seconds(1))
        await store.receive(\.tick)
        await store.skipInFlightEffects()
    }

    @Test func timerSleepsUntilTheNextFire() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-5)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.tick)
        await harness.clock.advance(by: .seconds(4))
        await harness.clock.advance(by: .seconds(1))
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.runs.value.isEmpty)
    }

    @Test func timerWaitsAtLeastOneSecond() async {
        let schedule = ScheduleFixtures.schedule(
            1,
            trigger: .interval(value: 10, unit: .seconds),
            activatedAt: now.addingTimeInterval(-9.5)
        )
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([schedule]))

        await store.send(.tick)
        await harness.clock.advance(by: .milliseconds(500))
        await harness.clock.advance(by: .milliseconds(500))
        await store.receive(\.tick)
        await store.skipInFlightEffects()
    }
}
#endif
