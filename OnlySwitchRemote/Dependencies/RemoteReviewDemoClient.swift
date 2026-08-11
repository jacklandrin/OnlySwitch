import Foundation
import Network
import RemoteCore

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
    private var catalogs: [UUID: RemoteCatalogCache] = [:]
    private var statuses: [UUID: [RemoteControlStatus]] = [:]
    private var tombstones: Set<UUID> = []
    private var preparedPairings: [UUID: PreparedPairing] = [:]
    private var preparedPairingRecord: PreparedPairingPersistenceRecord?
    private var eventContinuations: [UUID: AsyncStream<RemoteConnectionEvent>.Continuation] = [:]
    private var eventBacklog: [RemoteConnectionEvent] = []

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
            setForegrounded: { _ in }
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
            loadCatalog: { await runtime.catalog(for: $0) },
            saveCatalog: { await runtime.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await runtime.statuses(for: $0) },
            saveStatuses: { await runtime.setStatuses($1, for: $0) },
            replaceStatusSnapshot: { await runtime.setStatuses($1, for: $0) },
            mergeStatus: { await runtime.mergeStatus($1, for: $0) },
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
