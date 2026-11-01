import Foundation
import Network
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

    private var hasCompletedInitialSetup = true
    private var pairedMacs: [PairedMac] = []
    private var selectedMacID: UUID? = studioMacID
    private var authenticatedMacID: UUID? = studioMacID
    private var authenticatedSessionID: UUID? = sessionID
    private var layouts: [UUID: MacDashboardLayout] = [:]
    private var systemMonitorLayouts: [UUID: MacSystemMonitorLayout] = [:]
    private var catalogs: [UUID: RemoteCatalogCache] = [:]
    private var statuses: [UUID: [RemoteControlStatus]] = [:]
    private var tombstones: Set<UUID> = []
    private var preparedPairings: [UUID: PreparedPairing] = [:]
    private var preparedPairingRecord: PreparedPairingPersistenceRecord?
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
        return .init(contentType: item.contentType, data: data)
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

    func appState() -> (Bool, [PairedMac], UUID?) {
        (hasCompletedInitialSetup, pairedMacs, selectedMacID)
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) {
        selectedMacID = intent.selectedMacID
        hasCompletedInitialSetup = intent.hasCompletedInitialSetup
    }

    func setInitialSetupCompleted(_ value: Bool) { hasCompletedInitialSetup = value }
    func setPairedMacs(_ value: [PairedMac]) { pairedMacs = value.filter { tombstones.contains($0.id) == false } }
    func upsert(_ mac: PairedMac) {
        guard tombstones.contains(mac.id) == false else { return }
        pairedMacs.removeAll { $0.id == mac.id }
        pairedMacs.append(mac)
    }
    func updateRequiresPairing(_ id: UUID, value: Bool) {
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].requiresPairing = value
    }
    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) {
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].lastEndpointDescription = description
        pairedMacs[index].lastConnectedAt = connectedAt
    }
    func removePairedMac(_ id: UUID) {
        pairedMacs.removeAll { $0.id == id }
        if selectedMacID == id { selectedMacID = pairedMacs.first?.id }
    }
    func setSelectedMacID(_ id: UUID?) { selectedMacID = id }
    func layout(for id: UUID) -> MacDashboardLayout? { tombstones.contains(id) ? nil : layouts[id] }
    func setLayout(_ layout: MacDashboardLayout) { if tombstones.contains(layout.macID) == false { layouts[layout.macID] = layout } }
    func systemMonitorLayout(for id: UUID) -> MacSystemMonitorLayout? {
        tombstones.contains(id) ? nil : systemMonitorLayouts[id]
    }
    func setSystemMonitorLayout(_ layout: MacSystemMonitorLayout) {
        if tombstones.contains(layout.macID) == false { systemMonitorLayouts[layout.macID] = layout }
    }
    func catalog(for id: UUID) -> RemoteCatalogCache? { tombstones.contains(id) ? nil : catalogs[id] }
    func setCatalog(_ catalog: RemoteCatalogCache, for id: UUID) { if tombstones.contains(id) == false { catalogs[id] = catalog } }
    func statuses(for id: UUID) -> [RemoteControlStatus]? { tombstones.contains(id) ? nil : statuses[id] }
    func setStatuses(_ value: [RemoteControlStatus], for id: UUID) { if tombstones.contains(id) == false { statuses[id] = value } }
    func mergeStatus(_ status: RemoteControlStatus, for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        var values = statuses[id] ?? []
        values.removeAll { $0.id == status.id }
        values.append(status)
        statuses[id] = values
    }
    func markTombstoned(_ id: UUID) { tombstones.insert(id) }
    func isTombstoned(_ id: UUID) -> Bool { tombstones.contains(id) }
    func forget(_ id: UUID) {
        tombstones.insert(id)
        removePairedMac(id)
        layouts[id] = nil
        systemMonitorLayouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
    }

    func preparePairingState(
        _ mac: PairedMac,
        transactionID: UUID,
        credentialVerifier: Data
    ) -> PreparedPairingPersistenceRecord {
        let previous = RemotePairingRollbackState(
            pairedMacs: pairedMacs,
            selectedMacID: selectedMacID,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            tombstonedMacIDs: tombstones
        )
        let record = PreparedPairingPersistenceRecord(
            transactionID: transactionID,
            candidate: mac,
            candidateCredentialVerifier: credentialVerifier,
            previous: previous
        )
        preparedPairingRecord = record
        return record
    }

    func loadPreparedPairingState() -> PreparedPairingPersistenceRecord? { preparedPairingRecord }
    func adoptPreparedPairingState(_ transactionID: UUID) throws {
        guard var record = preparedPairingRecord, record.transactionID == transactionID else { throw RemoteDependencyError.unimplemented }
        record.phase = .adopted
        preparedPairingRecord = record
        upsert(record.candidate)
        selectedMacID = record.candidate.id
    }
    func finalizePairingState(_ transactionID: UUID) throws {
        guard preparedPairingRecord?.transactionID == transactionID else { throw RemoteDependencyError.unimplemented }
        preparedPairingRecord = nil
    }
    func restorePairingState(_ record: PreparedPairingPersistenceRecord) {
        pairedMacs = record.previous.pairedMacs
        selectedMacID = record.previous.selectedMacID
        hasCompletedInitialSetup = record.previous.hasCompletedInitialSetup
        tombstones = record.previous.tombstonedMacIDs
        preparedPairingRecord = nil
    }
    func commitPairingAndSelect(_ mac: PairedMac) -> RemotePairingPersistenceSnapshot {
        let snapshot = RemotePairingPersistenceSnapshot(
            previousMac: pairedMacs.first(where: { $0.id == mac.id }),
            previousSelectedMacID: selectedMacID,
            wasTombstoned: tombstones.contains(mac.id)
        )
        tombstones.remove(mac.id)
        upsert(mac)
        selectedMacID = mac.id
        hasCompletedInitialSetup = true
        return snapshot
    }
    func restorePairingSnapshot(macID: UUID, snapshot: RemotePairingPersistenceSnapshot) {
        pairedMacs.removeAll { $0.id == macID }
        if let previousMac = snapshot.previousMac { pairedMacs.append(previousMac) }
        selectedMacID = snapshot.previousSelectedMacID
        if snapshot.wasTombstoned { tombstones.insert(macID) } else { tombstones.remove(macID) }
    }

    private var canonicalDiscoveredMacs: [DiscoveredMac] {
        [
            .init(id: Self.studioMacID, displayName: "Studio", endpoint: .hostPort(host: "studio.local", port: 41_210), protocolVersion: .current),
            .init(id: Self.travelMacID, displayName: "Travel", endpoint: .hostPort(host: "travel.local", port: 41_211), protocolVersion: .current),
        ]
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

    private nonisolated static func makeBrightnessSnapshot() -> RemoteBrightnessSnapshot {
        .init(revision: 1, displays: [
            .init(id: 1, name: "Built-in Retina Display", control: .native, level: 0.7, hasError: false),
            .init(id: 2, name: "Studio Display", control: .ddc, level: 0.5, hasError: false),
        ])
    }

    /// Sample screenshots: a title, an SF Symbol and a gradient, drawn on demand (no bundled assets).
    private struct DemoScreenshot: Sendable {
        let id: UUID
        let title: String
        let symbolName: String
        /// Gradient start and end as 0xRRGGBB.
        let colors: (UInt32, UInt32)
        let isPinned: Bool
        let minutesAgo: Double
    }

    private nonisolated static let demoScreenshots: [DemoScreenshot] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D101")!, title: "Release Notes", symbolName: "doc.text.fill",
              colors: (0x4B3FD8, 0x9B4DDB), isPinned: true, minutesAgo: 240),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D102")!, title: "Dashboard", symbolName: "chart.bar.xaxis",
              colors: (0x1FA5B8, 0x2D6BE4), isPinned: false, minutesAgo: 5),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D103")!, title: "Design Review", symbolName: "paintpalette.fill",
              colors: (0xF2994A, 0xE0457B), isPinned: false, minutesAgo: 45),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D104")!, title: "Terminal", symbolName: "terminal.fill",
              colors: (0x3A3F47, 0x111316), isPinned: false, minutesAgo: 180),
    ]

    /// Four PNG screenshots in the Mac's display order (pinned first, then newest first).
    nonisolated static func makeScreenshotLibrary() -> RemoteScreenshotLibrary {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = demoScreenshots.map { shot in
            RemoteScreenshotItem(
                id: shot.id,
                fileName: "\(shot.title).png",
                contentType: "public.png",
                createdAt: now.addingTimeInterval(-shot.minutesAgo * 60),
                isPinned: shot.isPinned,
                revision: 1,
                byteCount: 180_000
            )
        }
        return .init(revision: 1, isCollectionEnabled: true, items: items)
    }

    private nonisolated static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Renders a 16:10 sample screenshot `width` points wide at scale 1, so pixels equal points.
    nonisolated static func demoScreenshotImage(for item: RemoteScreenshotItem, width: CGFloat) -> UIImage {
        let shot = demoScreenshots.first { $0.id == item.id }
        let size = CGSize(width: width, height: (width * 10 / 16).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = shot?.colors ?? (0x8E8E93, 0x48484A)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [cgColor(colors.0), cgColor(colors.1)] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            let unit = size.height / 10
            let configuration = UIImage.SymbolConfiguration(pointSize: unit * 2.6, weight: .semibold)
            if let symbol = UIImage(systemName: shot?.symbolName ?? "photo", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: unit * 2.4))
            }
            let title = (shot?.title ?? item.fileName) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: unit * 0.9, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: unit * 6.4), withAttributes: attributes)
        }
    }

    private nonisolated static func makeSoundMixerSnapshot() -> RemoteSoundMixerSnapshot {
        .init(
            revision: 1,
            isEnabled: true,
            systemVolume: 62,
            output: .init(name: "Studio Display Speakers", symbolName: "display"),
            apps: [
                .init(
                    id: "com.apple.Music",
                    name: "Music",
                    volume: 80,
                    isMuted: false,
                    equalizer: .init(gains: [3, 2, 1, 0, -1, 0, 1, 2, 3, 2], status: .active),
                    routing: .init(selectedDeviceIDs: [], status: .followingSystem)
                ),
                .init(
                    id: "com.apple.Safari",
                    name: "Safari",
                    volume: 45,
                    isMuted: false,
                    equalizer: .init(gains: [], status: .flat),
                    routing: .init(selectedDeviceIDs: [], status: .followingSystem)
                ),
            ],
            outputDevices: [
                .init(id: "review-studio-display", name: "Studio Display Speakers", isDefault: true),
                .init(id: "review-airpods", name: "AirPods Pro", isDefault: false),
            ]
        )
    }

    private nonisolated static func makeDescriptor(
        id: RemoteControlID,
        title: String,
        behavior: RemoteControlDescriptor.Behavior,
        icon: String,
        supportsStatus: Bool
    ) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: title,
            behavior: behavior,
            icon: .systemSymbol(icon),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: supportsStatus,
            supportsSecondaryInformation: supportsStatus
        )
    }

    private nonisolated static func makeStatus(
        id: RemoteControlID,
        isOn: Bool,
        revision: UInt64,
        updatedAt: Date
    ) -> RemoteControlStatus {
        .init(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: isOn,
            secondaryInformation: isOn ? "On" : "Off",
            isProcessing: false,
            revision: revision,
            updatedAt: updatedAt
        )
    }
}

extension RemoteConnectionClient {
    static func reviewDemo(runtime: RemoteReviewDemoRuntime) -> Self {
        Self(
            discover: {
                AsyncStream { continuation in
                    let task = Task {
                        for event in await runtime.discoveryEvents() { continuation.yield(event) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            restartDiscovery: {},
            preparePairing: { discoveredMac, code, _ in
                try await runtime.preparePairing(discoveredMac: discoveredMac, code: code)
            },
            finalizePairing: { try await runtime.finalizePairing(transactionID: $0) },
            abortPairing: { await runtime.abortPairing(transactionID: $0) },
            select: { await runtime.select($0) },
            events: {
                let id = UUID()
                return AsyncStream { continuation in
                    let registration = Task { await runtime.registerEvents(id: id, continuation: continuation) }
                    continuation.onTermination = { _ in
                        registration.cancel()
                        Task {
                            await registration.value
                            await runtime.unregisterEvents(id: id)
                        }
                    }
                }
            },
            snapshot: { await runtime.connectionSnapshot() },
            adoptPairedMac: { await runtime.adopt($0) },
            forgetMac: { await runtime.forget($0) },
            subscribe: { try await runtime.subscribe($0) },
            send: { try await runtime.send($0) },
            fetchCodexUsage: { invocation in
                let snapshot = await runtime.connectionSnapshot()
                guard invocation.macID == snapshot.authenticatedMacID,
                      invocation.sessionID == snapshot.authenticatedSessionID else {
                    throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
                }
                return .init(
                    requestID: invocation.request.requestID,
                    result: .success(.init(
                        account: .init(email: "review@example.com", plan: "Plus"),
                        session: .init(remainingPercent: 82, resetAt: Date(timeIntervalSince1970: 1_800_003_600)),
                        weekly: .init(remainingPercent: 64, resetAt: Date(timeIntervalSince1970: 1_800_604_800)),
                        resetCredits: .available(count: 3, expiresAt: Date(timeIntervalSince1970: 1_800_086_400)),
                        creditBalance: .available(remaining: 12.5, limit: 50, unit: "credits"),
                        source: .oauth,
                        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                        activity: invocation.request.includeLocalActivity ? .init(
                            dailyUsage: [.init(date: Date(timeIntervalSince1970: 1_800_000_000), tokenCount: 12_345)],
                            isPartial: false
                        ) : nil
                    ))
                )
            },
            fetchClaudeUsage: { invocation in
                let snapshot = await runtime.connectionSnapshot()
                guard invocation.macID == snapshot.authenticatedMacID, invocation.sessionID == snapshot.authenticatedSessionID else {
                    throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
                }
                return .init(requestID: invocation.request.requestID, result: .success(.init(
                    account: .init(email: "review@example.com", plan: "Pro"),
                    session: .init(remainingPercent: 75, resetAt: Date(timeIntervalSince1970: 1_800_003_600)),
                    weekly: .init(remainingPercent: 64, resetAt: Date(timeIntervalSince1970: 1_800_604_800)),
                    models: [.init(id: "seven_day_sonnet", name: "Sonnet", quota: .init(remainingPercent: 90, resetAt: nil))],
                    extraUsage: .init(isEnabled: false, used: nil, limit: nil, currency: nil, utilization: nil),
                    fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)) ))
            },
            sendSoundMixer: { await runtime.sendSoundMixer($0) },
            setSystemMonitorStreaming: { _ in },
            setSoundMixerStreaming: { await runtime.setSoundMixerStreaming($0) },
            setBrightnessStreaming: { await runtime.setBrightnessStreaming($0) },
            sendBrightness: { await runtime.sendBrightness($0) },
            setScreenshotsStreaming: { await runtime.setScreenshotsStreaming($0) },
            fetchScreenshotThumbnails: { try await runtime.screenshotThumbnails($0) },
            fetchScreenshotImage: { try await runtime.screenshotImage($0) },
            deleteScreenshots: { try await runtime.deleteScreenshots($0) },
            setForegrounded: { _ in },
            // The demo never closes its session in the background, so a transfer needs no hold.
            withBackgroundTransferHold: { try await $0() }
        )
    }
}

extension RemotePersistenceClient {
    static func reviewDemo(runtime: RemoteReviewDemoRuntime) -> Self {
        Self(
            saveAppState: { await runtime.saveAppState($0) },
            loadInitialSetupCompleted: { await runtime.appState().0 },
            saveInitialSetupCompleted: { await runtime.setInitialSetupCompleted($0) },
            loadPairedMacs: { await runtime.appState().1 },
            savePairedMacs: { await runtime.setPairedMacs($0) },
            upsertPairedMac: { await runtime.upsert($0) },
            updateRequiresPairing: { await runtime.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { await runtime.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { await runtime.removePairedMac($0) },
            loadSelectedMacID: { await runtime.appState().2 },
            saveSelectedMacID: { await runtime.setSelectedMacID($0) },
            loadLayout: { await runtime.layout(for: $0) },
            saveLayout: { await runtime.setLayout($0) },
            loadSystemMonitorLayout: { await runtime.systemMonitorLayout(for: $0) },
            saveSystemMonitorLayout: { await runtime.setSystemMonitorLayout($0) },
            loadCatalog: { await runtime.catalog(for: $0) },
            saveCatalog: { await runtime.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await runtime.statuses(for: $0) },
            saveStatuses: { await runtime.setStatuses($1, for: $0) },
            replaceStatusSnapshot: { await runtime.setStatuses($1, for: $0) },
            mergeStatus: { await runtime.mergeStatus($1, for: $0) },
            loadAphroditeLibrary: { _ in nil },
            replaceAphroditeLibrary: { _, _ in },
            markMacTombstoned: { await runtime.markTombstoned($0) },
            preparePairingState: { await runtime.preparePairingState($0, transactionID: $1, credentialVerifier: $2) },
            loadPreparedPairingState: { await runtime.loadPreparedPairingState() },
            adoptPreparedPairingState: { try await runtime.adoptPreparedPairingState($0) },
            finalizePairingState: { try await runtime.finalizePairingState($0) },
            restorePairingState: { await runtime.restorePairingState($0) },
            commitPairing: { _ = await runtime.commitPairingAndSelect($0) },
            commitPairingAndSelect: { await runtime.commitPairingAndSelect($0) },
            restorePairingSnapshot: { await runtime.restorePairingSnapshot(macID: $0, snapshot: $1) },
            isMacTombstoned: { await runtime.isTombstoned($0) },
            forgetMac: { await runtime.forget($0) }
        )
    }
}

extension RemoteScreenshotCacheClient {
    /// The review demo's own cache in the temporary directory, apart from `Caches/OnlyRemote/Screenshots`.
    static var reviewDemo: Self {
        live(root: FileManager.default.temporaryDirectory.appendingPathComponent("OnlyRemoteReviewDemo/Screenshots", isDirectory: true))
    }
}

extension RemoteScreenshotImageClient {
    /// Loads demo originals through the demo connection into the demo cache, never the live ones.
    static func reviewDemo(connection: RemoteConnectionClient, cache: RemoteScreenshotCacheClient) -> Self {
        .live(
            cache: cache,
            fetchImage: { try await connection.fetchScreenshotImage($0) },
            holdTransfer: { try await connection.withBackgroundTransferHold($0) },
            makeRequestID: { UUID() }
        )
    }
}
