import ComposableArchitecture
import Testing
@testable import SoundMixerEQ

@MainActor
struct EqualizerFeatureTests {
    @Test func appDisclosuresAreIndependentAndPreserveSettings() async {
        var settings = EqualizerSettings.flat
        settings.setGain(-6, band: 5)
        var initial = EqualizerFeature.State()
        initial.apps["music"] = .init(source: source("music"), settings: settings)
        initial.apps["browser"] = .init(source: source("browser"))
        let store = TestStore(initialState: initial) { EqualizerFeature() }
        await store.send(.toggleExpanded("music")) { $0.apps["music"]?.isExpanded = true }
        await store.send(.toggleExpanded("browser")) { $0.apps["browser"]?.isExpanded = true }
        await store.send(.toggleExpanded("music")) { $0.apps["music"]?.isExpanded = false }
        #expect(store.state.apps["music"]?.settings == settings)
        #expect(store.state.apps["browser"]?.isExpanded == true)
    }

    @Test func persistentEditsAndResetPublishAndSaveTheirExactSettings() async {
        let saves = LockIsolated<[(String, EqualizerSettings)]>([])
        let applies = LockIsolated<[(String, EqualizerSettings)]>([])
        var initial = EqualizerFeature.State()
        initial.apps["com.apple.Music"] = .init(source: source("com.apple.Music"))
        let store = TestStore(initialState: initial) { EqualizerFeature() } withDependencies: {
            $0.equalizerClient.save = { id, settings in saves.withValue { $0.append((id, settings)) } }
            $0.equalizerClient.apply = { id, settings in
                applies.withValue { $0.append((id, settings)) }
                return settings.isFlat ? .flat : .active
            }
        }
        var boosted = EqualizerSettings.flat
        boosted.setGain(12, band: 5)
        await store.send(.setGain("com.apple.Music", 5, 99)) {
            $0.apps["com.apple.Music"]?.settings = boosted
            $0.apps["com.apple.Music"]?.revision = 1
            $0.saved["com.apple.Music"] = boosted
        }
        await store.receive(\.applicationResponse) { $0.apps["com.apple.Music"]?.status = .active }
        await store.send(.reset("com.apple.Music")) {
            $0.apps["com.apple.Music"]?.settings = .flat
            $0.apps["com.apple.Music"]?.revision = 2
            $0.saved["com.apple.Music"] = nil
        }
        await store.receive(\.applicationResponse) { $0.apps["com.apple.Music"]?.status = .flat }
        #expect(saves.value.map(\.0) == ["com.apple.Music", "com.apple.Music"])
        #expect(saves.value.map(\.1) == [boosted, .flat])
        #expect(applies.value.map(\.1) == [boosted, .flat])
        await store.finish()
    }

    @Test func pidOnlySourcesDoNotPersistAndFailuresRemainVisible() async {
        let saves = LockIsolated<[String]>([])
        var initial = EqualizerFeature.State()
        initial.apps["pid-42"] = .init(source: source("pid-42", persistent: false))
        let store = TestStore(initialState: initial) { EqualizerFeature() } withDependencies: {
            $0.equalizerClient.save = { id, _ in saves.withValue { $0.append(id) } }
            $0.equalizerClient.apply = { _, _ in .unavailable }
        }
        var requested = EqualizerSettings.flat
        requested.setGain(-8, band: 2)
        await store.send(.setGain("pid-42", 2, -8)) {
            $0.apps["pid-42"]?.settings = requested
            $0.apps["pid-42"]?.revision = 1
        }
        await store.receive(\.applicationResponse) { $0.apps["pid-42"]?.status = .unavailable }
        #expect(saves.value.isEmpty)
        #expect(store.state.saved.isEmpty)
        #expect(store.state.apps["pid-42"]?.settings == requested)
        await store.finish()
    }

    @Test func loadingAndSourceRefreshRetainSavedEQAndIndependentDisclosure() async {
        var settings = EqualizerSettings.flat
        settings.setGain(-9, band: 6)
        let loaded = settings
        let store = TestStore(initialState: EqualizerFeature.State()) { EqualizerFeature() } withDependencies: {
            $0.equalizerClient.load = { ["com.apple.Music": loaded] }
        }
        await store.send(.load) { $0.saved = ["com.apple.Music": loaded] }
        let waiting = source("com.apple.Music", available: false)
        await store.send(.sourcesChanged([waiting])) {
            var app = EqualizerFeature.App(source: waiting, settings: loaded)
            app.revision = 1
            app.status = .pending
            $0.apps[waiting.id] = app
        }
        await store.send(.toggleExpanded(waiting.id)) { $0.apps[waiting.id]?.isExpanded = true }
        await store.send(.sourcesChanged([waiting])) { $0.apps[waiting.id]?.revision = 2 }
        #expect(store.state.apps[waiting.id]?.settings == loaded)
        #expect(store.state.apps[waiting.id]?.isExpanded == true)
        await store.send(.sourcesChanged([])) { $0.apps = [:] }
        #expect(store.state.settings(for: waiting.id) == loaded)
    }

    @Test func staleApplyResultsAndInvalidBandChangesAreIgnored() async {
        var initial = EqualizerFeature.State()
        var app = EqualizerFeature.App(source: source("music"))
        app.revision = 5
        app.status = .active
        initial.apps["music"] = app
        let store = TestStore(initialState: initial) { EqualizerFeature() }
        await store.send(.applicationResponse("music", 4, .unavailable))
        await store.send(.setGain("music", -1, 12))
        await store.send(.setGain("music", 10, 12))
        #expect(store.state.apps["music"]?.status == .active)
        #expect(store.state.apps["music"]?.settings == .flat)
    }

    private func source(_ id: String, persistent: Bool = true, available: Bool = true) -> EqualizerFeature.Source {
        .init(id: id, isPersistent: persistent, isSupported: true, isAvailable: available)
    }
}
