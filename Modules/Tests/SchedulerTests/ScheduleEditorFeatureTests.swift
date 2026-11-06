#if os(macOS)
import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

@MainActor
struct ScheduleEditorFeatureTests {
    let now = ScheduleFixtures.date(2026, 11, 4, 12, 0)
    let authorizationRequests = LockIsolated(0)

    private func makeStore(
        _ state: ScheduleEditorFeature.State,
        authorizes: Bool = true
    ) -> TestStoreOf<ScheduleEditorFeature> {
        let requests = authorizationRequests
        return TestStore(initialState: state) {
            ScheduleEditorFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.uuid = .incrementing
            $0.scheduleNotifications = ScheduleNotificationClient(
                requestAuthorization: {
                    requests.withValue { $0 += 1 }
                    return authorizes
                },
                post: { _, _ in }
            )
        }
    }

    private let focus = ScheduleTarget(controlID: .shortcut("Focus"), title: "Focus", behavior: .button)
    private let darkMode = ScheduleTarget(controlID: .builtIn("darkMode"), title: "Dark Mode", behavior: .switch)
    private let emptyTrash = ScheduleTarget(controlID: .builtIn("emptyTrash"), title: "Empty Trash", behavior: .button)

    // MARK: - Target selection

    @Test func selectingATargetUsesTheCatalogEntryAndFixesTheAction() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog))

        await store.send(.targetSelected(.shortcut("Focus"))) {
            $0.draft.target = focus
            $0.draft.action = .run
            $0.draft.name = "Focus"
        }

        #expect(store.state.allowedActions == [.run])
    }

    @Test func selectingAnotherTargetRenamesOnlyAnAutomaticName() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog))

        await store.send(.targetSelected(.shortcut("Focus"))) {
            $0.draft.target = focus
            $0.draft.action = .run
            $0.draft.name = "Focus"
        }
        await store.send(.targetSelected(.builtIn("darkMode"))) {
            $0.draft.target = darkMode
            $0.draft.action = .turnOn
            $0.draft.name = "Dark Mode"
        }
        await store.send(.binding(.set(\.draft.name, "Night"))) {
            $0.draft.name = "Night"
        }
        await store.send(.targetSelected(.builtIn("emptyTrash"))) {
            $0.draft.target = emptyTrash
            $0.draft.action = .run
        }
    }

    @Test func selectingAnUnknownTargetChangesNothing() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog))

        await store.send(.targetSelected(.shortcut("Missing")))
    }

    // MARK: - Saving

    @Test func savingAnInvalidDraftShowsIssuesAndSendsNoDelegate() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog))

        await store.send(.saveTapped) {
            $0.issues = [.missingTarget]
        }
    }

    @Test func savingAValidNewDraftClearsIssuesAndDelegatesTheSchedule() async {
        var state = ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog)
        state.issues = [.missingTarget]
        let store = makeStore(state)

        await store.send(.targetSelected(.shortcut("Focus"))) {
            $0.draft.target = focus
            $0.draft.action = .run
            $0.draft.name = "Focus"
        }
        await store.send(.saveTapped) {
            $0.issues = []
        }
        await store.receive(.delegate(.save(Schedule(
            id: ScheduleFixtures.id(0),
            name: "Focus",
            target: focus,
            action: .run,
            trigger: .weekly(days: [], hour: 9, minute: 0),
            activatedAt: now
        ))))
    }

    @Test func savingAChangedTriggerResetsTheAnchor() async {
        let original = ScheduleFixtures.schedule(
            1,
            trigger: .hourly(minute: 0),
            activatedAt: now.addingTimeInterval(-3600),
            lastFiredAt: now.addingTimeInterval(-600)
        )
        let store = makeStore(ScheduleEditorFeature.State(original: original, catalog: []))

        await store.send(.binding(.set(\.draft.hourlyMinute, 30))) {
            $0.draft.hourlyMinute = 30
        }
        await store.send(.saveTapped)

        var expected = original
        expected.trigger = .hourly(minute: 30)
        expected.activatedAt = now
        await store.receive(.delegate(.save(expected)))
    }

    @Test func savingAnUnchangedTriggerKeepsTheAnchorAndID() async {
        let original = ScheduleFixtures.schedule(1, trigger: .hourly(minute: 0), activatedAt: now.addingTimeInterval(-3600))
        let store = makeStore(ScheduleEditorFeature.State(original: original, catalog: []))

        await store.send(.binding(.set(\.draft.name, "Renamed"))) {
            $0.draft.name = "Renamed"
        }
        await store.send(.saveTapped)

        var expected = original
        expected.name = "Renamed"
        await store.receive(.delegate(.save(expected)))
    }

    @Test func discardingDelegatesTheDiscard() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: []))

        await store.send(.discardTapped)
        await store.receive(.delegate(.discard))
    }

    // MARK: - Notifications

    @Test func turningNotificationsOnRequestsAuthorizationOnlyOnce() async {
        let store = makeStore(ScheduleEditorFeature.State(original: nil, catalog: []), authorizes: false)

        await store.send(.notificationToggled(true)) {
            $0.draft.notifies = true
            $0.hasRequestedNotificationAuthorization = true
        }
        await store.receive(.notificationAuthorization(false)) {
            $0.isNotificationAuthorized = false
        }
        await store.send(.notificationToggled(false)) {
            $0.draft.notifies = false
        }
        await store.send(.notificationToggled(true)) {
            $0.draft.notifies = true
        }

        #expect(authorizationRequests.value == 1)
    }

    @Test func turningNotificationsOffNeverRequestsAuthorization() async {
        var state = ScheduleEditorFeature.State(original: nil, catalog: [])
        state.draft.notifies = true
        let store = makeStore(state)

        await store.send(.notificationToggled(false)) {
            $0.draft.notifies = false
        }

        #expect(authorizationRequests.value == 0)
    }

    // MARK: - Derived state

    @Test func aNewDraftIsDirtyOnlyOnceEdited() {
        var state = ScheduleEditorFeature.State(original: nil, catalog: [])
        #expect(!state.isDirty)

        state.draft.name = "Morning"
        #expect(state.isDirty)
    }

    @Test func anExistingScheduleIsDirtyOnlyWhenItsDraftDiffers() {
        let original = ScheduleFixtures.schedule(1, trigger: .hourly(minute: 0), activatedAt: now)
        var state = ScheduleEditorFeature.State(original: original, catalog: [])
        #expect(!state.isDirty)

        state.draft.hourlyMinute = 15
        #expect(state.isDirty)
    }

    @Test func targetIsUnavailableOnlyWhenALoadedCatalogLacksTheOriginalTarget() {
        let original = ScheduleFixtures.schedule(1, controlID: .builtIn("gone"), trigger: .hourly(minute: 0), activatedAt: now)
        let present = ScheduleFixtures.schedule(2, controlID: .builtIn("darkMode"), trigger: .hourly(minute: 0), activatedAt: now)

        #expect(!ScheduleEditorFeature.State(original: original, catalog: []).targetIsUnavailable)
        #expect(ScheduleEditorFeature.State(original: original, catalog: ScheduleFixtures.catalog).targetIsUnavailable)
        #expect(!ScheduleEditorFeature.State(original: present, catalog: ScheduleFixtures.catalog).targetIsUnavailable)
        #expect(!ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog).targetIsUnavailable)
    }

    @Test func targetTitlePrefersTheCatalogOverTheSavedTitle() {
        let saved = ScheduleFixtures.schedule(1, controlID: .builtIn("darkMode"), trigger: .hourly(minute: 0), activatedAt: now)
        let missing = ScheduleFixtures.schedule(2, controlID: .builtIn("gone"), trigger: .hourly(minute: 0), activatedAt: now)

        #expect(ScheduleEditorFeature.State(original: saved, catalog: ScheduleFixtures.catalog).targetTitle == "Dark Mode")
        #expect(ScheduleEditorFeature.State(original: missing, catalog: ScheduleFixtures.catalog).targetTitle == "Target 2")
        #expect(ScheduleEditorFeature.State(original: nil, catalog: ScheduleFixtures.catalog).targetTitle == nil)
    }

    @Test func allowedActionsFollowTheTargetBehavior() {
        var state = ScheduleEditorFeature.State(original: nil, catalog: [])
        #expect(state.allowedActions == [.turnOn, .turnOff, .toggle])

        state.draft.target = focus
        #expect(state.allowedActions == [.run])
    }
}
#endif
