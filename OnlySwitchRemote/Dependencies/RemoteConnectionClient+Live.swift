import Foundation

extension RemoteConnectionClient {
    static var live: Self {
        let runtime = RemoteConnectionRuntime(
            persistence: .live,
            keychain: .live,
            screenshotCache: .live,
            backgroundTasks: .live
        )
        return Self(
            discover: { runtime.makeDiscoveryStream() },
            restartDiscovery: { await runtime.restartDiscovery() },
            preparePairing: { try await runtime.preparePairing($0, code: $1, deviceName: $2) },
            finalizePairing: { try await runtime.finalizePairing($0) },
            abortPairing: { await runtime.abortPairing($0) },
            select: { await runtime.select($0) },
            events: { runtime.makeConnectionEventStream() },
            snapshot: { await runtime.snapshot() },
            adoptPairedMac: { await runtime.adoptPairedMac($0) },
            forgetMac: { try await runtime.forgetMac($0) },
            subscribe: { try await runtime.subscribe($0) },
            send: { try await runtime.send($0) },
            fetchCodexUsage: { try await runtime.fetchCodexUsage($0) },
            fetchClaudeUsage: { try await runtime.fetchClaudeUsage($0) },
            sendSoundMixer: { try await runtime.sendSoundMixer($0) },
            setSystemMonitorStreaming: { try await runtime.setSystemMonitorStreaming($0) },
            setSoundMixerStreaming: { try await runtime.setSoundMixerStreaming($0) },
            setBrightnessStreaming: { try await runtime.setBrightnessStreaming($0) },
            sendBrightness: { try await runtime.sendBrightness($0) },
            setScreenshotsStreaming: { try await runtime.setScreenshotsStreaming($0) },
            fetchScreenshotThumbnails: { try await runtime.fetchScreenshotThumbnails($0) },
            fetchScreenshotImage: { try await runtime.fetchScreenshotImage($0) },
            deleteScreenshots: { try await runtime.deleteScreenshots($0) },
            setForegrounded: { await runtime.setForegrounded($0) },
            withBackgroundTransferHold: { try await runtime.withBackgroundTransferHold($0) }
        )
    }
}


enum RemoteDeviceIdentity {
    static let key = "remoteDeviceID"
    static var name: String { ProcessInfo.processInfo.hostName }

    static func load() -> UUID {
        if let value = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) { return value }
        let value = UUID()
        UserDefaults.standard.set(value.uuidString, forKey: key)
        return value
    }
}
