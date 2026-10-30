import ComposableArchitecture
import RemoteCore
import SoundMixerEQ
import Testing
@testable import OnlySwitch

@MainActor
struct SoundMixerRemoteBridgeTests {
    private func routingState() -> OutputRoutingFeature.State {
        var state = OutputRoutingFeature.State()
        state.devices = [.init(id: "spk", name: "Speakers", isDefault: true, channelCount: 2),
                         .init(id: "hp", name: "AirPods", isDefault: false, channelCount: 2)]
        state.apps["music"] = .init(source: .init(id: "music", isPersistent: true, isSupported: true, isAvailable: true),
                                    selection: .init(deviceUIDs: ["hp"]))
        state.apps["music"]?.status = .active
        return state
    }

    @Test func snapshotIncludesEqualizerRoutingAndDevices() {
        var eq = EqualizerFeature.State()
        eq.apps["music"] = .init(source: .init(id: "music", isPersistent: true, isSupported: true, isAvailable: true),
                                 settings: .init(gains: [3, 0, -2]))
        eq.apps["music"]?.status = .active
        let snapshot = SoundMixerRemoteBridge.snapshot(
            revision: 9, isEnabled: true, systemVolume: 40, isSystemVolumeAvailable: false, output: nil,
            rows: [.init(id: "music", name: "Music", volume: 30, isMuted: false)],
            equalizer: eq, routing: routingState()
        )
        #expect(snapshot.isSystemVolumeAvailable == false)
        #expect(snapshot.outputDevices.map(\.id) == ["spk", "hp"])
        #expect(snapshot.apps[0].equalizer == .init(gains: [3, 0, -2], status: .active))
        #expect(snapshot.apps[0].routing == .init(selectedDeviceIDs: ["hp"], status: .active))
    }

    @Test func disabledMixerSendsNoApps() {
        let snapshot = SoundMixerRemoteBridge.snapshot(
            revision: 1, isEnabled: false, systemVolume: 40, isSystemVolumeAvailable: true, output: nil,
            rows: [.init(id: "music", name: "Music", volume: 30, isMuted: false)],
            equalizer: .init(), routing: .init()
        )
        #expect(snapshot.apps.isEmpty)
        #expect(snapshot.outputDevices.isEmpty)
    }

    @Test func validationRejectsUnknownRowsBandsAndDevices() {
        let routing = routingState()
        #expect(throws: RemoteProtocolError.self) {
            try SoundMixerRemoteBridge.validate(.setAppVolume(id: "gone", volume: 3), rowIDs: ["music"], routing: routing)
        }
        #expect(throws: RemoteProtocolError.self) {
            try SoundMixerRemoteBridge.validate(.setAppEqualizerGain(id: "music", band: 10, gain: 1), rowIDs: ["music"], routing: routing)
        }
        #expect(throws: RemoteProtocolError.self) {
            try SoundMixerRemoteBridge.validate(.toggleAppOutputDevice(id: "music", deviceID: "unknown"), rowIDs: ["music"], routing: routing)
        }
    }

    @Test func validationClampsAndAllowsDeselectingOfflineDevice() throws {
        var routing = routingState()
        routing.devices.removeAll { $0.id == "hp" } // selected device unplugged
        #expect(try SoundMixerRemoteBridge.validate(.setSystemVolume(140), rowIDs: [], routing: routing) == .systemVolume(100))
        #expect(try SoundMixerRemoteBridge.validate(.setAppEqualizerGain(id: "music", band: 2, gain: 40), rowIDs: ["music"], routing: routing)
                == .equalizerGain("music", 2, 12))
        #expect(try SoundMixerRemoteBridge.validate(.toggleAppOutputDevice(id: "music", deviceID: "hp"), rowIDs: ["music"], routing: routing)
                == .toggleOutput("music", "hp"))
    }

    @Test func processingCommandsRejectRowsWithoutAudioProcessing() throws {
        let routing = routingState()
        let rowIDs: Set<String> = ["music", OwnPlaybackSource.rowID]
        let own = OwnPlaybackSource.rowID
        for command: RemoteSoundMixerCommand in [
            .setAppEqualizerGain(id: own, band: 0, gain: 3),
            .resetAppEqualizer(id: own),
            .toggleAppOutputDevice(id: own, deviceID: "spk"),
            .followSystemOutput(id: own),
        ] {
            #expect(throws: RemoteProtocolError.self) {
                try SoundMixerRemoteBridge.validate(command, rowIDs: rowIDs, routing: routing)
            }
        }
        #expect(try SoundMixerRemoteBridge.validate(.setAppVolume(id: own, volume: 30), rowIDs: rowIDs, routing: routing)
                == .appVolume(own, 30))
        #expect(try SoundMixerRemoteBridge.validate(.setAppMuted(id: own, isMuted: true), rowIDs: rowIDs, routing: routing)
                == .appMuted(own, true))
    }
}
