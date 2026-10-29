import ComposableArchitecture
import Testing
@testable import SoundMixerEQ

@MainActor
struct OutputRoutingFeatureTests {
    @Test func appsKeepIndependentMultiSelectionAndFollowSystemIntent() async {
        var initial = OutputRoutingFeature.State()
        initial.devices = [device("a"), device("b")]
        initial.apps["music"] = .init(source: source("music", available: false))
        initial.apps["browser"] = .init(source: source("browser", available: false))
        let store = TestStore(initialState: initial) { OutputRoutingFeature() }
        let a = OutputRouteSelection(deviceUIDs: ["a"])
        let b = OutputRouteSelection(deviceUIDs: ["b"])
        let both = OutputRouteSelection(deviceUIDs: ["a", "b"])
        await store.send(.toggleDevice("music", "a")) {
            $0.apps["music"]?.selection = a
            $0.apps["music"]?.revision = 1
            $0.apps["music"]?.status = .pending
            $0.saved["music"] = a
        }
        await store.send(.toggleDevice("music", "b")) {
            $0.apps["music"]?.selection = both
            $0.apps["music"]?.revision = 2
            $0.saved["music"] = both
        }
        await store.send(.toggleDevice("browser", "b")) {
            $0.apps["browser"]?.selection = b
            $0.apps["browser"]?.revision = 1
            $0.apps["browser"]?.status = .pending
            $0.saved["browser"] = b
        }
        await store.send(.followSystem("music")) {
            $0.apps["music"]?.selection = .init()
            $0.apps["music"]?.revision = 3
            $0.saved["music"] = nil
        }
        #expect(store.state.selection(for: "music").followsSystem)
        #expect(store.state.selection(for: "browser") == b)
    }

    @Test func removingLastDevicePublishesAndPersistsFollowSystem() async {
        let saves = LockIsolated<[(String, OutputRouteSelection)]>([])
        let applies = LockIsolated<[(String, OutputRouteSelection)]>([])
        var initial = OutputRoutingFeature.State()
        initial.devices = [device("a")]
        var app = OutputRoutingFeature.App(source: source("com.apple.Music"), selection: .init(deviceUIDs: ["a"]))
        app.status = .active
        initial.apps[app.source.id] = app
        initial.saved[app.source.id] = app.selection
        let store = TestStore(initialState: initial) { OutputRoutingFeature() } withDependencies: {
            $0.outputRoutingClient.save = { id, selection in saves.withValue { $0.append((id, selection)) } }
            $0.outputRoutingClient.apply = { id, selection in
                applies.withValue { $0.append((id, selection)) }
                return .followingSystem
            }
        }
        await store.send(.toggleDevice(app.source.id, "a")) {
            $0.apps[app.source.id]?.selection = .init()
            $0.apps[app.source.id]?.revision = 1
            $0.saved[app.source.id] = nil
        }
        await store.receive(\.applicationResponse) { $0.apps[app.source.id]?.status = .followingSystem }
        #expect(saves.value.map(\.0) == [app.source.id])
        #expect(saves.value.map(\.1) == [OutputRouteSelection()])
        #expect(applies.value.map(\.1) == [OutputRouteSelection()])
        await store.finish()
    }

    @Test func pidOnlySelectionsApplyWithoutPersistence() async {
        let saves = LockIsolated<[String]>([])
        let applies = LockIsolated<[OutputRouteSelection]>([])
        var initial = OutputRoutingFeature.State()
        initial.devices = [device("a")]
        initial.apps["pid-42"] = .init(source: source("pid-42", persistent: false))
        let selection = OutputRouteSelection(deviceUIDs: ["a"])
        let store = TestStore(initialState: initial) { OutputRoutingFeature() } withDependencies: {
            $0.outputRoutingClient.save = { id, _ in saves.withValue { $0.append(id) } }
            $0.outputRoutingClient.apply = { _, selection in
                applies.withValue { $0.append(selection) }
                return .active
            }
        }
        await store.send(.toggleDevice("pid-42", "a")) {
            $0.apps["pid-42"]?.selection = selection
            $0.apps["pid-42"]?.revision = 1
        }
        await store.receive(\.applicationResponse) { $0.apps["pid-42"]?.status = .active }
        #expect(saves.value.isEmpty)
        #expect(store.state.saved.isEmpty)
        #expect(applies.value == [selection])
        await store.finish()
    }

    @Test func partialDisconnectAllMissingAndReconnectPreserveDesiredUIDsAndReleaseOldRoute() async {
        let a = device("a"), b = device("b")
        let connected = LockIsolated([a, b])
        let applies = LockIsolated<[OutputRouteSelection]>([])
        let saves = LockIsolated<[String]>([])
        let desired = OutputRouteSelection(deviceUIDs: ["a", "b"])
        var initial = OutputRoutingFeature.State()
        initial.devices = [a, b]
        initial.knownDevices = [a.id: a, b.id: b]
        var app = OutputRoutingFeature.App(source: source("music"), selection: desired)
        app.status = .active
        initial.apps["music"] = app
        initial.saved["music"] = desired
        let store = TestStore(initialState: initial) { OutputRoutingFeature() } withDependencies: {
            $0.outputRoutingClient.save = { id, _ in saves.withValue { $0.append(id) } }
            $0.outputRoutingClient.apply = { _, selection in
                applies.withValue { $0.append(selection) }
                let resolution = OutputRouteResolution(selection: selection, devices: connected.value)
                return resolution.isWaiting ? .waitingForDevices : (resolution.missingUIDs.isEmpty ? .active : .partial)
            }
        }
        connected.setValue([a])
        await store.send(.devicesChanged([a])) {
            $0.devices = [a]
            $0.apps["music"]?.revision = 1
        }
        await store.receive(\.applicationResponse) { $0.apps["music"]?.status = .partial }
        connected.setValue([])
        await store.send(.devicesChanged([])) {
            $0.devices = []
            $0.apps["music"]?.revision = 2
        }
        await store.receive(\.applicationResponse) { $0.apps["music"]?.status = .waitingForDevices }
        connected.setValue([a, b])
        await store.send(.devicesChanged([a, b])) {
            $0.devices = [a, b]
            $0.apps["music"]?.revision = 3
        }
        await store.receive(\.applicationResponse) { $0.apps["music"]?.status = .active }
        #expect(applies.value == [desired, desired, desired], "The all-offline request must reach the adapter to release its old route")
        #expect(store.state.selection(for: "music") == desired)
        #expect(store.state.saved["music"] == desired)
        #expect(store.state.knownDevices == [a.id: a, b.id: b])
        #expect(saves.value.isEmpty)
        await store.finish()
    }

    @Test func unknownUIDCannotBeAddedButSelectedOfflineUIDCanBeRemoved() async {
        let selected = OutputRouteSelection(deviceUIDs: ["gone"])
        var initial = OutputRoutingFeature.State()
        initial.devices = [device("a")]
        initial.apps["music"] = .init(source: source("music", available: false), selection: selected)
        initial.saved["music"] = selected
        let store = TestStore(initialState: initial) { OutputRoutingFeature() }
        await store.send(.toggleDevice("music", "forged"))
        await store.send(.toggleDevice("music", "gone")) {
            $0.apps["music"]?.selection = .init()
            $0.apps["music"]?.revision = 1
            $0.apps["music"]?.status = .pending
            $0.saved["music"] = nil
        }
        #expect(store.state.selection(for: "music").followsSystem)
    }

    @Test func persistedSelectionLoadsBeforeSourceAndStaleResponseCannotReplaceCurrentStatus() async {
        let selected = OutputRouteSelection(deviceUIDs: ["gone"])
        let store = TestStore(initialState: OutputRoutingFeature.State()) { OutputRoutingFeature() } withDependencies: {
            $0.outputRoutingClient.load = { ["music": selected] }
        }
        await store.send(.load) { $0.saved = ["music": selected] }
        let unavailableSource = source("music", available: false)
        await store.send(.sourcesChanged([unavailableSource])) {
            var app = OutputRoutingFeature.App(source: unavailableSource, selection: selected)
            app.revision = 1
            app.status = .waitingForDevices
            $0.apps["music"] = app
        }
        await store.send(.applicationResponse("music", 0, .active))
        #expect(store.state.apps["music"]?.status == .waitingForDevices)
        await store.send(.sourcesChanged([])) { $0.apps = [:] }
        #expect(store.state.selection(for: "music") == selected)
    }

    private func source(_ id: String, persistent: Bool = true, available: Bool = true) -> OutputRoutingFeature.Source {
        .init(id: id, isPersistent: persistent, isSupported: true, isAvailable: available)
    }
    private func device(_ id: String) -> OutputRouteDevice {
        .init(id: id, name: id, isDefault: id == "a", channelCount: 2)
    }
}
