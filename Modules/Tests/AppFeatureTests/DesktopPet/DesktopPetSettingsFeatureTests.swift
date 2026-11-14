import ComposableArchitecture
import RemoteCore
import Scheduler
import Testing
@testable import AppFeature

@MainActor
struct DesktopPetSettingsFeatureTests {
    let darkMode = descriptor(kind: .builtIn, value: "darkMode", title: "Dark Mode", behavior: .switch)
    let shortcut = descriptor(kind: .shortcut, value: "Hello", title: "Hello", behavior: .button)
    let offline = descriptor(kind: .builtIn, value: "offline", title: "Offline", behavior: .button, isAvailable: false)

    var darkModeTarget: ScheduleTarget {
        ScheduleTarget(controlID: darkMode.id, title: "Dark Mode", behavior: .switch)
    }

    @Test func taskLoadsSavedActionAndCatalog() async {
        let target = darkModeTarget
        let catalog = [darkMode, shortcut]
        let store = TestStore(initialState: DesktopPetSettingsFeature.State()) {
            DesktopPetSettingsFeature()
        } withDependencies: {
            $0.desktopPetClickActionStorage.load = { .control(target) }
            $0.scheduleExecutor.catalog = { catalog }
        }

        await store.send(.task) {
            $0.clickAction = .control(target)
            $0.mode = .control
        }
        await store.receive(\.catalogLoaded) {
            $0.catalog = catalog
        }
    }

    @Test func selectingTargetSavesControlAction() async {
        let saved = LockIsolated<[DesktopPetClickAction]>([])
        let store = TestStore(
            initialState: DesktopPetSettingsFeature.State(mode: .control, catalog: [darkMode, shortcut])
        ) {
            DesktopPetSettingsFeature()
        } withDependencies: {
            $0.desktopPetClickActionStorage.save = { action in saved.withValue { $0.append(action) } }
        }
        let expected = DesktopPetClickAction.control(
            ScheduleTarget(controlID: shortcut.id, title: "Hello", behavior: .button)
        )

        await store.send(.targetSelected(shortcut.id)) {
            $0.clickAction = expected
        }
        await store.finish()

        #expect(saved.value == [expected])
    }

    @Test func choosingOnlyControlSavesImmediately() async {
        let saved = LockIsolated<[DesktopPetClickAction]>([])
        let store = TestStore(
            initialState: DesktopPetSettingsFeature.State(clickAction: .control(darkModeTarget), mode: .control)
        ) {
            DesktopPetSettingsFeature()
        } withDependencies: {
            $0.desktopPetClickActionStorage.save = { action in saved.withValue { $0.append(action) } }
        }

        await store.send(.binding(.set(\.mode, .onlyControl))) {
            $0.mode = .onlyControl
            $0.clickAction = .onlyControl
        }
        await store.finish()

        #expect(saved.value == [.onlyControl])
    }

    @Test func choosingControlModeWithoutTargetKeepsOnlyControlSaved() async {
        let store = TestStore(initialState: DesktopPetSettingsFeature.State()) {
            DesktopPetSettingsFeature()
        }

        await store.send(.binding(.set(\.mode, .control))) {
            $0.mode = .control
        }
    }

    @Test func missingTargetIsReportedOnlyAfterCatalogLoads() {
        let gone = ScheduleTarget(
            controlID: RemoteControlID(kind: .evolution, value: "gone"),
            title: "Gone",
            behavior: .button
        )
        var state = DesktopPetSettingsFeature.State(clickAction: .control(gone), mode: .control)
        #expect(!state.isTargetMissing)

        state.catalog = [darkMode]

        #expect(state.isTargetMissing)
        #expect(state.targetTitle == "Gone")
    }

    @Test func targetTitlePrefersCatalogTitle() {
        let stale = ScheduleTarget(controlID: darkMode.id, title: "Dunkelmodus", behavior: .switch)
        let state = DesktopPetSettingsFeature.State(clickAction: .control(stale), mode: .control, catalog: [darkMode])

        #expect(state.targetTitle == "Dark Mode")
        #expect(!state.isTargetMissing)
    }

    @Test func unknownOrUnavailableSelectionIsIgnored() async {
        let store = TestStore(
            initialState: DesktopPetSettingsFeature.State(mode: .control, catalog: [darkMode, offline])
        ) {
            DesktopPetSettingsFeature()
        }

        await store.send(.targetSelected(RemoteControlID(kind: .shortcut, value: "missing")))
        await store.send(.targetSelected(offline.id))
    }
}

private func descriptor(
    kind: RemoteControlID.Kind,
    value: String,
    title: String,
    behavior: RemoteControlDescriptor.Behavior,
    isAvailable: Bool = true
) -> RemoteControlDescriptor {
    RemoteControlDescriptor(
        id: RemoteControlID(kind: kind, value: value),
        title: title,
        behavior: behavior,
        icon: .systemSymbol("circle"),
        isAvailable: isAvailable,
        unavailableReason: nil,
        isDestructive: false,
        supportsStatus: false,
        supportsSecondaryInformation: false
    )
}
