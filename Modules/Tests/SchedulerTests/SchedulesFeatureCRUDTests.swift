#if os(macOS)
import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

@MainActor
struct SchedulesFeatureCRUDTests {
    let now = ScheduleFixtures.date(2026, 11, 4, 12, 0)

    /// Hourly schedules anchored "now", so a tick never fires them.
    private func idle(_ number: Int, name: String? = nil) -> Schedule {
        ScheduleFixtures.schedule(number, name: name, trigger: .hourly(minute: 0), activatedAt: now)
    }

    private func editor(_ schedule: Schedule?, catalog: [RemoteControlDescriptor] = []) -> ScheduleEditorFeature.State {
        ScheduleEditorFeature.State(original: schedule, catalog: catalog)
    }

    private func editing(_ schedules: [Schedule], selected: Schedule) -> SchedulesFeature.State {
        var state = SchedulesFeature.State.loaded(schedules)
        state.selection = selected.id
        state.editor = editor(selected)
        return state
    }

    // MARK: - Adding and saving

    @Test func addingOpensANewDraftWithTheCatalogAndClearsTheSelection() async {
        let first = idle(1)
        var state = editing([first], selected: first)
        state.catalog = ScheduleFixtures.catalog
        state.editor = editor(first, catalog: ScheduleFixtures.catalog)
        let store = ScheduleEngineHarness(now: now).makeStore(state)

        await store.send(.addTapped) {
            $0.selection = nil
            $0.editor = editor(nil, catalog: ScheduleFixtures.catalog)
        }
        #expect(store.state.editor?.draft.isActive == true)
        #expect(store.state.editor?.draft.target == nil)
    }

    @Test func savingANewScheduleAppendsSelectsAndPersistsIt() async {
        let first = idle(1)
        var state = SchedulesFeature.State.loaded([first])
        state.catalog = ScheduleFixtures.catalog
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)
        let focus = ScheduleTarget(controlID: .shortcut("Focus"), title: "Focus", behavior: .button)

        await store.send(.addTapped) {
            $0.editor = editor(nil, catalog: ScheduleFixtures.catalog)
        }
        await store.send(.editor(.presented(.targetSelected(.shortcut("Focus"))))) {
            $0.editor?.draft.target = focus
            $0.editor?.draft.action = .run
            $0.editor?.draft.name = "Focus"
        }
        await store.send(.editor(.presented(.saveTapped)))

        let saved = Schedule(
            id: ScheduleFixtures.id(0),
            name: "Focus",
            target: focus,
            action: .run,
            trigger: .weekly(days: [], hour: 9, minute: 0),
            activatedAt: now
        )
        await store.receive(.editor(.presented(.delegate(.save(saved))))) {
            $0.schedules.append(saved)
            $0.selection = saved.id
            $0.editor = editor(saved, catalog: ScheduleFixtures.catalog)
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.saves.value == [[first, saved]])
        #expect(store.state.editor?.isDirty == false)
        #expect(harness.runs.value.isEmpty)
    }

    @Test func savingClearsCorruptedStorageSoTheListIsWritten() async {
        let saved = idle(1)
        var state = SchedulesFeature.State.loaded([])
        state.isStorageCorrupted = true
        state.editor = editor(nil)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.editor(.presented(.delegate(.save(saved))))) {
            $0.schedules = [saved]
            $0.selection = saved.id
            $0.isStorageCorrupted = false
            $0.editor = editor(saved)
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.saves.value == [[saved]])
    }

    @Test func savingAnEditedTriggerUpdatesInPlaceAndResetsTheAnchor() async {
        let first = ScheduleFixtures.schedule(
            1,
            trigger: .hourly(minute: 0),
            activatedAt: now.addingTimeInterval(-7200),
            lastFiredAt: now.addingTimeInterval(-60)
        )
        let second = idle(2)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(editing([first, second], selected: first))

        await store.send(.editor(.presented(.binding(.set(\.draft.hourlyMinute, 30))))) {
            $0.editor?.draft.hourlyMinute = 30
        }
        await store.send(.editor(.presented(.saveTapped)))

        var edited = first
        edited.trigger = .hourly(minute: 30)
        edited.activatedAt = now
        await store.receive(.editor(.presented(.delegate(.save(edited))))) {
            $0.schedules[id: first.id] = edited
            $0.editor = editor(edited)
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.saves.value == [[edited, second]])
        #expect(harness.saves.value.last?.first?.lastFiredAt == first.lastFiredAt)
        #expect(harness.runs.value.isEmpty)
    }

    // MARK: - Discarding

    @Test func discardingAnEditResetsTheDraft() async {
        let first = idle(1)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(editing([first], selected: first))

        await store.send(.editor(.presented(.binding(.set(\.draft.name, "Changed"))))) {
            $0.editor?.draft.name = "Changed"
        }
        await store.send(.editor(.presented(.discardTapped)))
        await store.receive(.editor(.presented(.delegate(.discard)))) {
            $0.editor = editor(first)
        }

        #expect(harness.saves.value.isEmpty)
    }

    @Test func discardingANewDraftClosesTheEditor() async {
        var state = SchedulesFeature.State.loaded([idle(1)])
        state.editor = editor(nil)
        state.editor?.draft.name = "Draft"
        let store = ScheduleEngineHarness(now: now).makeStore(state)

        await store.send(.editor(.presented(.discardTapped)))
        await store.receive(.editor(.presented(.delegate(.discard)))) {
            $0.editor = nil
        }
        #expect(store.state.selection == nil)
    }

    // MARK: - Selection

    @Test func selectingWithACleanEditorSwitchesImmediately() async {
        let first = idle(1)
        let second = idle(2)
        let store = ScheduleEngineHarness(now: now).makeStore(editing([first, second], selected: first))

        await store.send(.select(second.id)) {
            $0.selection = second.id
            $0.editor = editor(second)
        }
        await store.send(.select(second.id))
        await store.send(.select(nil)) {
            $0.selection = nil
            $0.editor = nil
        }
    }

    @Test func selectingWithUnsavedChangesAsksAndDiscardSwitches() async {
        let first = idle(1)
        let second = idle(2)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(editing([first, second], selected: first))

        await store.send(.editor(.presented(.binding(.set(\.draft.name, "Changed"))))) {
            $0.editor?.draft.name = "Changed"
        }
        await store.send(.select(second.id)) {
            $0.alert = SchedulesFeature.unsavedChangesAlert(.discardAndSelect(second.id))
        }
        await store.send(.alert(.presented(.discardAndSelect(second.id)))) {
            $0.alert = nil
            $0.selection = second.id
            $0.editor = editor(second)
        }

        #expect(harness.saves.value.isEmpty)
    }

    @Test func cancellingTheUnsavedAlertKeepsTheEdit() async {
        let first = idle(1)
        let second = idle(2)
        let store = ScheduleEngineHarness(now: now).makeStore(editing([first, second], selected: first))

        await store.send(.editor(.presented(.binding(.set(\.draft.name, "Changed"))))) {
            $0.editor?.draft.name = "Changed"
        }
        await store.send(.select(second.id)) {
            $0.alert = SchedulesFeature.unsavedChangesAlert(.discardAndSelect(second.id))
        }
        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }

        #expect(store.state.selection == first.id)
        #expect(store.state.editor?.draft.name == "Changed")
    }

    @Test func addingWithUnsavedChangesAsksAndDiscardOpensANewDraft() async {
        let first = idle(1)
        let store = ScheduleEngineHarness(now: now).makeStore(editing([first], selected: first))

        await store.send(.editor(.presented(.binding(.set(\.draft.name, "Changed"))))) {
            $0.editor?.draft.name = "Changed"
        }
        await store.send(.addTapped) {
            $0.alert = SchedulesFeature.unsavedChangesAlert(.discardAndAdd)
        }
        await store.send(.alert(.presented(.discardAndAdd))) {
            $0.alert = nil
            $0.selection = nil
            $0.editor = editor(nil)
        }
    }

    // MARK: - Deleting

    @Test func confirmingADeleteRemovesPersistsAndClosesTheEditor() async {
        let first = idle(1, name: "Morning")
        let second = idle(2)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(editing([first, second], selected: first))

        await store.send(.deleteTapped(first.id)) {
            $0.alert = SchedulesFeature.deleteAlert(for: first)
        }
        await store.send(.alert(.presented(.confirmDelete(first.id)))) {
            $0.alert = nil
            $0.schedules = [second]
            $0.selection = nil
            $0.editor = nil
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.saves.value == [[second]])
    }

    @Test func deletingAnotherScheduleKeepsTheSelection() async {
        let first = idle(1)
        let second = idle(2)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(editing([first, second], selected: second))

        await store.send(.deleteTapped(first.id)) {
            $0.alert = SchedulesFeature.deleteAlert(for: first)
        }
        await store.send(.alert(.presented(.confirmDelete(first.id)))) {
            $0.alert = nil
            $0.schedules = [second]
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()

        #expect(harness.saves.value == [[second]])
    }

    @Test func cancellingADeleteKeepsTheSchedule() async {
        let first = idle(1)
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(.loaded([first]))

        await store.send(.deleteTapped(first.id)) {
            $0.alert = SchedulesFeature.deleteAlert(for: first)
        }
        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }

        #expect(harness.saves.value.isEmpty)
    }

    @Test func deletingARunningScheduleLetsTheRunFinishAndIgnoresIt() async {
        let first = idle(1)
        var state = SchedulesFeature.State.loaded([first])
        state.running = [first.id]
        let harness = ScheduleEngineHarness(now: now)
        let store = harness.makeStore(state)

        await store.send(.deleteTapped(first.id)) {
            $0.alert = SchedulesFeature.deleteAlert(for: first)
        }
        await store.send(.alert(.presented(.confirmDelete(first.id)))) {
            $0.alert = nil
            $0.schedules = []
        }
        await store.receive(\.tick)
        await store.skipInFlightEffects()
        #expect(store.state.running == [first.id])

        await store.send(.runFinished(first.id, .succeeded, at: now)) {
            $0.running = []
        }

        #expect(harness.saves.value == [[]])
        #expect(harness.notifications.value.isEmpty)
    }

    // MARK: - Catalog and search

    @Test func aLoadedCatalogReachesTheOpenEditor() async {
        let first = ScheduleFixtures.schedule(1, controlID: .builtIn("gone"), trigger: .hourly(minute: 0), activatedAt: now)
        let store = ScheduleEngineHarness(now: now).makeStore(editing([first], selected: first))

        await store.send(.catalogLoaded(ScheduleFixtures.catalog)) {
            $0.catalog = ScheduleFixtures.catalog
            $0.editor?.catalog = ScheduleFixtures.catalog
        }

        #expect(store.state.editor?.targetIsUnavailable == true)
    }

    @Test(arguments: [
        ("", [1, 2, 3]),
        ("   ", [1, 2, 3]),
        ("morning", [1]),
        ("CAFE", [2]),
        ("dark", [3]),
        ("target 2", [2]),
        ("nothing", []),
    ])
    func searchFiltersByNameAndTargetTitle(query: String, expected: [Int]) {
        let morning = idle(1, name: "Morning Lights")
        let cafe = idle(2, name: "Café")
        var other = idle(3, name: "Other")
        other.target.title = "Dark Mode"
        var state = SchedulesFeature.State.loaded([morning, cafe, other])
        state.searchText = query

        #expect(state.filteredSchedules.map(\.id) == expected.map(ScheduleFixtures.id))
    }
}
#endif
