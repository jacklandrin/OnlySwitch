import ComposableArchitecture
import DisplayBrightness
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitch

@MainActor
struct RemoteBrightnessProviderTests {
    private let displays = [
        BrightnessDisplay(id: 1, name: "Built-in", control: .native, level: 0.6),
        BrightnessDisplay(id: 2, name: "LG", control: .unavailable, level: 1, error: true),
    ]

    private func makeStore(_ state: DisplayBrightnessFeature.State = .init()) -> StoreOf<DisplayBrightnessFeature> {
        Store(initialState: state) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient = .testValue
        }
    }

    @Test func mapsSnapshot() {
        let remote = RemoteBrightnessProvider.remoteSnapshot(from: .init(generation: 3, displays: displays), revision: 5)
        #expect(remote.revision == 5)
        #expect(remote.displays == [
            .init(id: 1, name: "Built-in", control: .native, level: 0.6, hasError: false),
            .init(id: 2, name: "LG", control: .unavailable, level: 1, hasError: true),
        ])
    }

    @Test func setLevelValidatesDisplayAndClamps() throws {
        var state = DisplayBrightnessFeature.State()
        state.snapshot = .init(generation: 1, displays: displays)
        let provider = RemoteBrightnessProvider(store: makeStore(state))

        #expect(throws: RemoteProtocolError.self) { try provider.perform(.setLevel(displayID: 99, level: 0.5)) }
        #expect(throws: RemoteProtocolError.self) { try provider.perform(.setLevel(displayID: 2, level: 0.5)) }

        let result = try provider.perform(.setLevel(displayID: 1, level: 3))
        #expect(result.displays.first?.level == 1)
        let lowered = try provider.perform(.setLevel(displayID: 1, level: -2))
        #expect(lowered.displays.first?.level == 0)
        #expect(lowered.revision > result.revision)
    }

    @Test func streamRegistersAndReleasesHost() async {
        let store = makeStore()
        let provider = RemoteBrightnessProvider(store: store, pollInterval: .milliseconds(10))
        let host = UUID()

        var registered = false
        for await _ in provider.snapshots(hostID: host) {
            registered = store.hosts.contains(host)
            break
        }
        #expect(registered)

        // `onTermination` releases the host through a MainActor hop.
        for _ in 0..<100 where store.hosts.contains(host) {
            await Task.yield()
        }
        #expect(store.hosts.contains(host) == false)
    }
}
