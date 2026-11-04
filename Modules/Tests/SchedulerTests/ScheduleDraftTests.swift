#if os(macOS)
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

struct ScheduleDraftTests {
    private let switchTarget = ScheduleTarget(controlID: RemoteControlID(kind: .builtIn, value: "DarkMode"), title: "Dark Mode", behavior: .switch)
    private let buttonTarget = ScheduleTarget(controlID: RemoteControlID(kind: .builtIn, value: "EmptyTrash"), title: "  Empty Trash  ", behavior: .button)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_900_000_000)

    private func validDraft() -> ScheduleDraft {
        var draft = ScheduleDraft()
        draft.setTarget(switchTarget)
        return draft
    }

    private func savedSchedule(isActive: Bool = true) -> Schedule {
        Schedule(
            id: UUID(),
            name: "Night",
            isActive: isActive,
            notifies: true,
            target: switchTarget,
            action: .turnOff,
            trigger: .weekly(days: [.monday, .friday], hour: 22, minute: 30),
            activatedAt: earlier,
            lastFiredAt: earlier.addingTimeInterval(60),
            lastOutcome: .failed("boom"),
            lastRunAt: earlier.addingTimeInterval(61)
        )
    }

    @Test func missingTargetIsReported() {
        #expect(ScheduleDraft().issues().contains(.missingTarget))
    }

    @Test func validDraftHasNoIssues() {
        #expect(validDraft().issues().isEmpty)
    }

    @Test func buttonTargetRejectsTurnOn() {
        var draft = ScheduleDraft()
        draft.target = buttonTarget
        draft.action = .turnOn
        #expect(draft.issues() == [.actionNotAllowed])
    }

    @Test func setTargetPicksAnAllowedAction() {
        var draft = ScheduleDraft()
        draft.action = .turnOff
        draft.setTarget(buttonTarget)
        #expect(draft.action == .run)
        draft.setTarget(switchTarget)
        #expect(draft.action == .turnOn)
    }

    @Test func setTargetKeepsAnAllowedAction() {
        var draft = ScheduleDraft()
        draft.action = .turnOff
        draft.setTarget(switchTarget)
        #expect(draft.action == .turnOff)
    }

    @Test func intervalBelowMinimumIsTooShort() {
        var draft = validDraft()
        draft.triggerKind = .interval
        draft.intervalValue = 9
        draft.intervalUnit = .seconds
        #expect(draft.issues() == [.intervalTooShort])
        draft.intervalValue = ScheduleCalendar.minimumIntervalSeconds
        #expect(draft.issues().isEmpty)
    }

    @Test func intervalAboveMaximumIsTooLong() {
        var draft = validDraft()
        draft.triggerKind = .interval
        draft.intervalValue = 8 * 24
        draft.intervalUnit = .hours
        #expect(draft.issues() == [.intervalTooLong])
        draft.intervalValue = 7 * 24
        #expect(draft.issues().isEmpty)
    }

    @Test func overflowingIntervalIsTooLong() {
        var draft = validDraft()
        draft.triggerKind = .interval
        draft.intervalValue = .max
        draft.intervalUnit = .hours
        #expect(draft.issues() == [.intervalTooLong])
    }

    @Test(arguments: [-1, 60])
    func hourlyMinuteOutOfRangeIsInvalid(minute: Int) {
        var draft = validDraft()
        draft.triggerKind = .hourly
        draft.hourlyMinute = minute
        #expect(draft.issues() == [.invalidMinute])
    }

    @Test func weeklyHourAndMinuteAreValidated() {
        var draft = validDraft()
        draft.triggerKind = .weekly
        draft.weeklyHour = 24
        #expect(draft.issues() == [.invalidHour])
        draft.weeklyHour = 23
        draft.weeklyMinute = 60
        #expect(draft.issues() == [.invalidMinute])
    }

    @Test func triggerReflectsKind() {
        var draft = validDraft()
        draft.intervalValue = 15
        draft.intervalUnit = .minutes
        draft.hourlyMinute = 5
        draft.weeklyDays = [.sunday]
        draft.weeklyHour = 7
        draft.weeklyMinute = 45
        draft.triggerKind = .interval
        #expect(draft.trigger == .interval(value: 15, unit: .minutes))
        draft.triggerKind = .hourly
        #expect(draft.trigger == .hourly(minute: 5))
        draft.triggerKind = .weekly
        #expect(draft.trigger == .weekly(days: [.sunday], hour: 7, minute: 45))
    }

    @Test func makeScheduleThrowsAllIssues() {
        var draft = ScheduleDraft()
        draft.triggerKind = .hourly
        draft.hourlyMinute = 99
        #expect(throws: ScheduleDraftIssues(issues: [.missingTarget, .invalidMinute])) {
            try draft.makeSchedule(original: nil, id: UUID(), now: now)
        }
    }

    @Test func emptyNameBecomesTrimmedTargetTitle() throws {
        var draft = ScheduleDraft()
        draft.setTarget(buttonTarget)
        draft.name = "   "
        let schedule = try draft.makeSchedule(original: nil, id: UUID(), now: now)
        #expect(schedule.name == "Empty Trash")
    }

    @Test func nameIsTrimmed() throws {
        var draft = validDraft()
        draft.name = "  Evening  "
        let schedule = try draft.makeSchedule(original: nil, id: UUID(), now: now)
        #expect(schedule.name == "Evening")
    }

    @Test func newScheduleUsesGivenIDAndNow() throws {
        let id = UUID()
        let schedule = try validDraft().makeSchedule(original: nil, id: id, now: now)
        #expect(schedule.id == id)
        #expect(schedule.activatedAt == now)
        #expect(schedule.lastFiredAt == nil)
        #expect(schedule.lastOutcome == nil)
        #expect(schedule.lastRunAt == nil)
    }

    @Test(arguments: [true, false])
    func unchangedDraftRoundTrips(isActive: Bool) throws {
        let original = savedSchedule(isActive: isActive)
        let draft = ScheduleDraft(original)
        let schedule = try draft.makeSchedule(original: original, id: UUID(), now: now)
        #expect(schedule == original)
    }

    @Test(arguments: [
        ScheduleTrigger.interval(value: 90, unit: .seconds),
        .hourly(minute: 59),
        .weekly(days: [], hour: 0, minute: 0),
    ])
    func initRestoresEveryTriggerKind(trigger: ScheduleTrigger) {
        var original = savedSchedule()
        original.trigger = trigger
        #expect(ScheduleDraft(original).trigger == trigger)
    }

    @Test func changingTriggerResetsActivatedAt() throws {
        let original = savedSchedule()
        var draft = ScheduleDraft(original)
        draft.weeklyMinute = 31
        let schedule = try draft.makeSchedule(original: original, id: UUID(), now: now)
        #expect(schedule.activatedAt == now)
        #expect(schedule.id == original.id)
        #expect(schedule.lastFiredAt == original.lastFiredAt)
        #expect(schedule.lastOutcome == original.lastOutcome)
        #expect(schedule.lastRunAt == original.lastRunAt)
    }

    @Test func reactivatingResetsActivatedAt() throws {
        let original = savedSchedule(isActive: false)
        var draft = ScheduleDraft(original)
        draft.isActive = true
        let schedule = try draft.makeSchedule(original: original, id: UUID(), now: now)
        #expect(schedule.isActive)
        #expect(schedule.activatedAt == now)
    }

    @Test func otherEditsKeepActivatedAt() throws {
        let original = savedSchedule()
        var draft = ScheduleDraft(original)
        draft.name = "Renamed"
        draft.notifies = false
        draft.action = .turnOn
        let schedule = try draft.makeSchedule(original: original, id: UUID(), now: now)
        #expect(schedule.name == "Renamed")
        #expect(schedule.notifies == false)
        #expect(schedule.action == .turnOn)
        #expect(schedule.activatedAt == original.activatedAt)
    }

    @Test func deactivatingKeepsActivatedAt() throws {
        let original = savedSchedule()
        var draft = ScheduleDraft(original)
        draft.isActive = false
        let schedule = try draft.makeSchedule(original: original, id: UUID(), now: now)
        #expect(schedule.isActive == false)
        #expect(schedule.activatedAt == original.activatedAt)
    }
}
#endif
