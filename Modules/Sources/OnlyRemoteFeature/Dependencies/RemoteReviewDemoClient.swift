import Foundation
import RemoteCore
import UIKit

actor RemoteReviewDemoRuntime {
    static let studioMacID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    static let travelMacID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
    static let pairingCode = "TEST23456789"

    private static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-00000000D010")!
    private static let darkModeID = RemoteControlID(kind: .builtIn, value: "2")
    private static let doNotDisturbID = RemoteControlID(kind: .builtIn, value: "4")
    private static let hideDesktopID = RemoteControlID(kind: .builtIn, value: "32")
    private static let shortcutID = RemoteControlID(kind: .shortcut, value: "review-focus")
    private static let evolutionID = RemoteControlID(kind: .evolution, value: "review-evolution")

    var hasCompletedInitialSetup = true
    var pairedMacs: [PairedMac] = []
    var selectedMacID: UUID? = studioMacID
    private var authenticatedMacID: UUID? = studioMacID
    private var authenticatedSessionID: UUID? = sessionID
    var layouts: [UUID: MacDashboardLayout] = [:]
    var systemMonitorLayouts: [UUID: MacSystemMonitorLayout] = [:]
    var catalogs: [UUID: RemoteCatalogCache] = [:]
    var statuses: [UUID: [RemoteControlStatus]] = [:]
    var tombstones: Set<UUID> = []
    private var preparedPairings: [UUID: PreparedPairing] = [:]
    var preparedPairingRecord: PreparedPairingPersistenceRecord?
    private var eventContinuations: [UUID: AsyncStream<RemoteConnectionEvent>.Continuation] = [:]
    private var eventBacklog: [RemoteConnectionEvent] = []
    private var soundMixerSnapshot = RemoteReviewDemoRuntime.makeSoundMixerSnapshot()
    private var isSoundMixerStreaming = false
    private var brightnessSnapshot = RemoteReviewDemoRuntime.makeBrightnessSnapshot()
    private var isBrightnessStreaming = false
    private var screenshotLibrary = RemoteReviewDemoRuntime.makeScreenshotLibrary()
    private var isScreenshotsStreaming = false

    init() {
        let connectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        pairedMacs = [
            .init(id: Self.studioMacID, displayName: "Studio", lastEndpointDescription: "studio.local", lastConnectedAt: connectedAt, requiresPairing: false),
            .init(id: Self.travelMacID, displayName: "Travel", lastEndpointDescription: "travel.local", lastConnectedAt: connectedAt.addingTimeInterval(-3_600), requiresPairing: false),
        ]
        let controls: [RemoteControlDescriptor] = [
            Self.makeDescriptor(id: Self.darkModeID, title: "Dark Mode", behavior: .switch, icon: "moon.fill", supportsStatus: true),
            Self.makeDescriptor(id: Self.doNotDisturbID, title: "Do Not Disturb", behavior: .switch, icon: "moon.circle.fill", supportsStatus: true),
            Self.makeDescriptor(id: Self.hideDesktopID, title: "Hide Desktop", behavior: .switch, icon: "rectangle.slash", supportsStatus: true),
            Self.makeDescriptor(id: Self.shortcutID, title: "Start Focus Session", behavior: .button, icon: "command", supportsStatus: false),
            Self.makeDescriptor(id: Self.evolutionID, title: "Review Workspace", behavior: .button, icon: "sparkles", supportsStatus: false),
        ]
        let order = controls.map(\.id)
        layouts = [
            Self.studioMacID: .init(macID: Self.studioMacID, selectedControlIDs: Set(order), order: order),
            Self.travelMacID: .init(macID: Self.travelMacID, selectedControlIDs: Set(order), order: order),
        ]
        systemMonitorLayouts = [
            Self.studioMacID: .default(macID: Self.studioMacID),
            Self.travelMacID: .default(macID: Self.travelMacID),
        ]
        let catalog = RemoteCatalogCache(revision: 42, controls: controls)
        catalogs = [Self.studioMacID: catalog, Self.travelMacID: catalog]
        let statusValues = [
            Self.makeStatus(id: Self.darkModeID, isOn: false, revision: 101, updatedAt: connectedAt),
            Self.makeStatus(id: Self.doNotDisturbID, isOn: true, revision: 102, updatedAt: connectedAt),
            Self.makeStatus(id: Self.hideDesktopID, isOn: false, revision: 103, updatedAt: connectedAt),
        ]
        statuses = [Self.studioMacID: statusValues, Self.travelMacID: statusValues]
    }

    func reset() {
        restoreCanonicalSeed()
    }

    func discoveryEvents() -> [DiscoveryEvent] {
        canonicalDiscoveredMacs.map(DiscoveryEvent.added)
    }

    func registerEvents(
        id: UUID,
        continuation: AsyncStream<RemoteConnectionEvent>.Continuation
    ) {
        eventContinuations[id] = continuation
        for event in eventBacklog { continuation.yield(event) }
        eventBacklog.removeAll()
    }

    func unregisterEvents(id: UUID) {
        eventContinuations[id] = nil
    }

    func connectionSnapshot() -> RemoteConnectionSnapshot {
        .init(
            selectedMacID: selectedMacID,
            authenticatedMacID: authenticatedMacID,
            authenticatedSessionID: authenticatedSessionID
        )
    }

    func preparePairing(
        discoveredMac: DiscoveredMac,
        code: String
    ) throws -> PreparedPairing {
        guard code == Self.pairingCode else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid pairing code")
        }
        guard let mac = pairedMacs.first(where: { $0.id == discoveredMac.id }) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid pairing code")
        }
        let transactionID = UUID()
        let prepared = PreparedPairing(
            transactionID: transactionID,
            mac: mac,
            catalog: catalogs[mac.id] ?? .init(revision: 1, controls: [])
        )
        preparedPairings[transactionID] = prepared
        return prepared
    }

    func finalizePairing(transactionID: UUID) throws -> PairedMac {
        guard let prepared = preparedPairings.removeValue(forKey: transactionID) else {
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing session expired")
        }
        selectedMacID = prepared.mac.id
        authenticatedMacID = prepared.mac.id
        authenticatedSessionID = Self.sessionID
        return prepared.mac
    }

    func abortPairing(transactionID: UUID?) {
        if let transactionID {
            preparedPairings[transactionID] = nil
        } else {
            preparedPairings.removeAll()
        }
    }

    func select(_ mac: PairedMac?) {
        selectedMacID = mac?.id
        guard let mac else {
            authenticatedMacID = nil
            authenticatedSessionID = nil
            return
        }
        authenticatedMacID = mac.id
        authenticatedSessionID = Self.sessionID
        publish(.sessionStarted(mac.id, Self.sessionID))
        publish(.authenticated(mac.id))
    }

    func adopt(_ mac: PairedMac) -> RemotePairAdoptionResult {
        select(mac)
        return .authenticated
    }

    func subscribe(_ controlIDs: Set<RemoteControlID>) throws {
        guard let macID = selectedMacID,
              let catalog = catalogs[macID]
        else { return }
        let selectedStatuses = (statuses[macID] ?? []).filter { controlIDs.contains($0.id) }
        publish(.catalog(macID, catalog.revision, catalog.controls))
        publish(.statusSnapshot(macID, selectedStatuses))
    }

    func setSoundMixerStreaming(_ enabled: Bool) {
        isSoundMixerStreaming = enabled
        guard enabled, let macID = authenticatedMacID else { return }
        publish(.soundMixer(macID, soundMixerSnapshot))
    }

    func sendSoundMixer(_ command: RemoteSoundMixerCommand) {
        let current = soundMixerSnapshot
        var systemVolume = current.systemVolume
        var apps = current.apps
        func update(_ id: String, _ transform: (RemoteSoundMixerApp) -> RemoteSoundMixerApp) {
            guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
            apps[index] = transform(apps[index])
        }
        switch command {
        case let .setSystemVolume(volume):
            systemVolume = volume
        case let .setAppVolume(id, volume):
            update(id) { .init(id: $0.id, name: $0.name, volume: volume, isMuted: $0.isMuted, equalizer: $0.equalizer, routing: $0.routing) }
        case let .setAppMuted(id, isMuted):
            update(id) { .init(id: $0.id, name: $0.name, volume: $0.volume, isMuted: isMuted, equalizer: $0.equalizer, routing: $0.routing) }
        case let .setAppEqualizerGain(id, band, gain):
            update(id) { app in
                guard let equalizer = app.equalizer, equalizer.gains.indices.contains(band) else { return app }
                var gains = equalizer.gains
                gains[band] = gain
                let status: RemoteSoundMixerEqualizer.Status = gains.allSatisfy { $0 == 0 } ? .flat : .active
                return .init(id: app.id, name: app.name, volume: app.volume, isMuted: app.isMuted, equalizer: .init(gains: gains, status: status), routing: app.routing)
            }
        case let .resetAppEqualizer(id):
            update(id) { app in
                guard app.equalizer != nil else { return app }
                return .init(id: app.id, name: app.name, volume: app.volume, isMuted: app.isMuted, equalizer: .init(gains: [], status: .flat), routing: app.routing)
            }
        case let .toggleAppOutputDevice(id, deviceID):
            guard current.outputDevices.contains(where: { $0.id == deviceID }) else { break }
            update(id) { app in
                guard let routing = app.routing else { return app }
                var selected = routing.selectedDeviceIDs
                if let index = selected.firstIndex(of: deviceID) { selected.remove(at: index) } else { selected.append(deviceID) }
                return .init(id: app.id, name: app.name, volume: app.volume, isMuted: app.isMuted, equalizer: app.equalizer, routing: .init(selectedDeviceIDs: selected, status: selected.isEmpty ? .followingSystem : .active))
            }
        case let .followSystemOutput(id):
            update(id) { app in
                guard app.routing != nil else { return app }
                return .init(id: app.id, name: app.name, volume: app.volume, isMuted: app.isMuted, equalizer: app.equalizer, routing: .init(selectedDeviceIDs: [], status: .followingSystem))
            }
        }
        soundMixerSnapshot = .init(
            revision: current.revision + 1,
            isEnabled: current.isEnabled,
            systemVolume: systemVolume,
            output: current.output,
            apps: apps,
            isSystemVolumeAvailable: current.isSystemVolumeAvailable,
            outputDevices: current.outputDevices
        )
        guard isSoundMixerStreaming, let macID = authenticatedMacID else { return }
        publish(.soundMixer(macID, soundMixerSnapshot))
    }

    func setBrightnessStreaming(_ enabled: Bool) {
        isBrightnessStreaming = enabled
        guard enabled, let macID = authenticatedMacID else { return }
        publish(.brightness(macID, brightnessSnapshot))
    }

    func sendBrightness(_ command: RemoteBrightnessCommand) {
        guard case let .setLevel(displayID, level) = command else { return }
        let displays = brightnessSnapshot.displays.map { display in
            guard display.id == displayID, display.control != .unavailable else { return display }
            return RemoteBrightnessDisplay(id: display.id, name: display.name, control: display.control, level: level, hasError: false)
        }
        brightnessSnapshot = .init(revision: brightnessSnapshot.revision + 1, displays: displays)
        guard isBrightnessStreaming, let macID = authenticatedMacID else { return }
        publish(.brightness(macID, brightnessSnapshot))
    }

    func setScreenshotsStreaming(_ enabled: Bool) {
        isScreenshotsStreaming = enabled
        guard enabled, let macID = authenticatedMacID else { return }
        publish(.screenshots(macID, screenshotLibrary))
    }

    func screenshotThumbnails(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotThumbnailsRequest>
    ) throws -> RemoteScreenshotThumbnailsResult {
        try requireScreenshotMac(invocation.macID)
        let request = invocation.request
        let thumbnails = screenshotLibrary.items.filter { request.ids.contains($0.id) }.compactMap { item in
            Self.demoScreenshotImage(for: item, width: CGFloat(RemoteScreenshotLimits.maximumThumbnailPixel))
                .jpegData(compressionQuality: 0.6)
                .flatMap { try? RemoteScreenshotThumbnail(itemID: item.id, revision: item.revision, jpegData: $0) }
        }
        return .init(
            requestID: request.requestID,
            thumbnails: thumbnails,
            missingIDs: request.ids.filter { id in thumbnails.contains { $0.itemID == id } == false }
        )
    }

    func screenshotImage(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotImageRequest>
    ) throws -> RemoteScreenshotImagePayload {
        try requireScreenshotMac(invocation.macID)
        let request = invocation.request
        guard let item = screenshotLibrary.items.first(where: { $0.id == request.itemID && $0.revision == request.revision }),
              let data = Self.demoScreenshotImage(for: item, width: 1_440).pngData() else {
            throw RemoteProtocolError(code: .controlNotFound, message: "The screenshot is no longer on the Mac")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)")
        try data.write(to: url)
        return .init(contentType: item.contentType, fileURL: url)
    }

    func deleteScreenshots(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotDeleteRequest>
    ) throws -> RemoteScreenshotDeleteResult {
        try requireScreenshotMac(invocation.macID)
        let request = invocation.request
        let remaining = screenshotLibrary.items.filter { request.ids.contains($0.id) == false }
        if remaining.count != screenshotLibrary.items.count {
            screenshotLibrary = .init(
                revision: screenshotLibrary.revision + 1,
                isCollectionEnabled: screenshotLibrary.isCollectionEnabled,
                items: remaining
            )
            if isScreenshotsStreaming, let macID = authenticatedMacID { publish(.screenshots(macID, screenshotLibrary)) }
        }
        // Ids that are already gone count as deleted, as on the Mac.
        return .init(requestID: request.requestID, failedIDs: [])
    }

    func send(_ invocation: RemoteActionInvocation) throws -> RemoteActionResult {
        guard invocation.macID == authenticatedMacID,
              invocation.sessionID == authenticatedSessionID,
              let catalog = catalogs[invocation.macID],
              let descriptor = catalog.controls.first(where: { $0.id == invocation.request.controlID })
        else {
            throw RemoteProtocolError(code: .controlNotFound, message: "Control not found")
        }

        let updatedStatus: RemoteControlStatus?
        if descriptor.supportsStatus {
            let current = statuses[invocation.macID]?.first(where: { $0.id == descriptor.id })
            let isOn: Bool?
            switch invocation.request.action {
            case let .setState(value): isOn = value
            case .trigger: isOn = current?.isOn
            }
            let status = RemoteControlStatus(
                id: descriptor.id,
                isAvailable: true,
                unavailableReason: nil,
                isOn: isOn,
                secondaryInformation: isOn.map { $0 ? "On" : "Off" },
                isProcessing: false,
                revision: (current?.revision ?? 0) + 1,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            mergeStatus(status, for: invocation.macID)
            updatedStatus = status
        } else {
            updatedStatus = nil
        }
        let result = RemoteActionResult(
            requestID: invocation.request.requestID,
            result: .success(updatedStatus)
        )
        publish(.action(invocation.macID, result))
        if let updatedStatus { publish(.status(invocation.macID, updatedStatus)) }
        return result
    }

    private func requireScreenshotMac(_ macID: UUID) throws {
        guard macID == authenticatedMacID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
    }

    private func publish(_ event: RemoteConnectionEvent) {
        guard eventContinuations.isEmpty == false else {
            eventBacklog.append(event)
            return
        }
        for continuation in eventContinuations.values { continuation.yield(event) }
    }

    private func restoreCanonicalSeed() {
        let connectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        pairedMacs = [
            .init(id: Self.studioMacID, displayName: "Studio", lastEndpointDescription: "studio.local", lastConnectedAt: connectedAt, requiresPairing: false),
            .init(id: Self.travelMacID, displayName: "Travel", lastEndpointDescription: "travel.local", lastConnectedAt: connectedAt.addingTimeInterval(-3_600), requiresPairing: false),
        ]
        let controls: [RemoteControlDescriptor] = [
            Self.makeDescriptor(id: Self.darkModeID, title: "Dark Mode", behavior: .switch, icon: "moon.fill", supportsStatus: true),
            Self.makeDescriptor(id: Self.doNotDisturbID, title: "Do Not Disturb", behavior: .switch, icon: "moon.circle.fill", supportsStatus: true),
            Self.makeDescriptor(id: Self.hideDesktopID, title: "Hide Desktop", behavior: .switch, icon: "rectangle.slash", supportsStatus: true),
            Self.makeDescriptor(id: Self.shortcutID, title: "Start Focus Session", behavior: .button, icon: "command", supportsStatus: false),
            Self.makeDescriptor(id: Self.evolutionID, title: "Review Workspace", behavior: .button, icon: "sparkles", supportsStatus: false),
        ]
        let order = controls.map(\.id)
        let layout = MacDashboardLayout(macID: Self.studioMacID, selectedControlIDs: Set(order), order: order)
        layouts = [Self.studioMacID: layout, Self.travelMacID: .init(macID: Self.travelMacID, selectedControlIDs: Set(order), order: order)]
        systemMonitorLayouts = [
            Self.studioMacID: .default(macID: Self.studioMacID),
            Self.travelMacID: .default(macID: Self.travelMacID),
        ]
        let catalog = RemoteCatalogCache(revision: 42, controls: controls)
        catalogs = [Self.studioMacID: catalog, Self.travelMacID: catalog]
        let statusValues = [
            Self.makeStatus(id: Self.darkModeID, isOn: false, revision: 101, updatedAt: connectedAt),
            Self.makeStatus(id: Self.doNotDisturbID, isOn: true, revision: 102, updatedAt: connectedAt),
            Self.makeStatus(id: Self.hideDesktopID, isOn: false, revision: 103, updatedAt: connectedAt),
        ]
        statuses = [Self.studioMacID: statusValues, Self.travelMacID: statusValues]
        hasCompletedInitialSetup = true
        selectedMacID = Self.studioMacID
        authenticatedMacID = Self.studioMacID
        authenticatedSessionID = Self.sessionID
        tombstones = []
        preparedPairings = [:]
        preparedPairingRecord = nil
        eventBacklog = []
        soundMixerSnapshot = Self.makeSoundMixerSnapshot()
        isSoundMixerStreaming = false
        brightnessSnapshot = Self.makeBrightnessSnapshot()
        isBrightnessStreaming = false
        screenshotLibrary = Self.makeScreenshotLibrary()
        isScreenshotsStreaming = false
    }
}
