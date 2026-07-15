import Foundation

struct RemotePairingSnapshot: Equatable, Sendable {
    let deviceID: UUID
    let epoch: UInt64
    let generation: UInt64
    let wasRevoked: Bool
}

struct RemoteHostLifecycle: Sendable {
    private enum Phase: Sendable {
        case stopped
        case starting(UInt64)
        case listening(UInt64)
    }

    let maximumPendingHandshakes: Int
    let maximumAuthenticatedSessions: Int

    private(set) var generation: UInt64 = 0
    private var phase: Phase = .stopped
    private var pendingSessions: Set<UUID> = []
    private var authenticatedDevices: [UUID: UUID] = [:]
    private var revokedDevices: Set<UUID> = []
    private var deviceEpochs: [UUID: UInt64] = [:]

    var pendingCount: Int { pendingSessions.count }
    var authenticatedCount: Int { authenticatedDevices.count }

    func isActive(generation candidate: UInt64) -> Bool {
        guard candidate == generation else { return false }
        switch phase {
        case let .starting(active), let .listening(active): return active == candidate
        case .stopped: return false
        }
    }

    init(maximumPendingHandshakes: Int = 8, maximumAuthenticatedSessions: Int = 8) {
        self.maximumPendingHandshakes = max(1, maximumPendingHandshakes)
        self.maximumAuthenticatedSessions = max(1, maximumAuthenticatedSessions)
    }

    mutating func beginStart() -> UInt64 {
        generation &+= 1
        phase = .starting(generation)
        pendingSessions.removeAll()
        authenticatedDevices.removeAll()
        return generation
    }

    mutating func markListening(generation candidate: UInt64) -> Bool {
        guard case let .starting(active) = phase,
              active == candidate,
              candidate == generation else { return false }
        phase = .listening(candidate)
        return true
    }

    func isListening(generation candidate: UInt64) -> Bool {
        guard case let .listening(active) = phase else { return false }
        return active == candidate && candidate == generation
    }

    mutating func acceptPending(sessionID: UUID, generation candidate: UInt64) -> Bool {
        guard isListening(generation: candidate),
              pendingSessions.count < maximumPendingHandshakes,
              authenticatedDevices[sessionID] == nil else { return false }
        return pendingSessions.insert(sessionID).inserted
    }

    func mayAuthorize(sessionID: UUID, deviceID: UUID, generation candidate: UInt64) -> Bool {
        isListening(generation: candidate)
            && pendingSessions.contains(sessionID)
            && revokedDevices.contains(deviceID) == false
            && authenticatedDevices.count < maximumAuthenticatedSessions
    }

    func isAuthorized(sessionID: UUID, deviceID: UUID, generation candidate: UInt64) -> Bool {
        isListening(generation: candidate)
            && authenticatedDevices[sessionID] == deviceID
            && revokedDevices.contains(deviceID) == false
    }

    mutating func authorize(
        sessionID: UUID,
        deviceID: UUID,
        generation candidate: UInt64,
        credentialExists: Bool
    ) -> Bool {
        guard credentialExists,
              mayAuthorize(sessionID: sessionID, deviceID: deviceID, generation: candidate) else { return false }
        pendingSessions.remove(sessionID)
        authenticatedDevices[sessionID] = deviceID
        return true
    }

    func pairingEpoch(for deviceID: UUID) -> UInt64 { deviceEpochs[deviceID, default: 0] }

    func pairingSnapshot(for deviceID: UUID, generation candidate: UInt64) -> RemotePairingSnapshot? {
        guard isListening(generation: candidate) else { return nil }
        return RemotePairingSnapshot(
            deviceID: deviceID,
            epoch: pairingEpoch(for: deviceID),
            generation: candidate,
            wasRevoked: revokedDevices.contains(deviceID)
        )
    }

    func validateRepair(_ snapshot: RemotePairingSnapshot) -> Bool {
        isListening(generation: snapshot.generation)
            && pairingEpoch(for: snapshot.deviceID) == snapshot.epoch
    }

    mutating func commitRepair(_ snapshot: RemotePairingSnapshot) -> Bool {
        guard validateRepair(snapshot) else { return false }
        revokedDevices.remove(snapshot.deviceID)
        return true
    }

    mutating func rollbackRepair(_ snapshot: RemotePairingSnapshot) -> Bool {
        guard pairingEpoch(for: snapshot.deviceID) == snapshot.epoch else { return false }
        if snapshot.wasRevoked {
            revokedDevices.insert(snapshot.deviceID)
        } else {
            revokedDevices.remove(snapshot.deviceID)
        }
        return true
    }

    func isRevoked(_ deviceID: UUID) -> Bool { revokedDevices.contains(deviceID) }

    mutating func allowRepairedDevice(
        _ deviceID: UUID,
        pairingEpoch: UInt64,
        generation candidate: UInt64
    ) -> Bool {
        let snapshot = RemotePairingSnapshot(
            deviceID: deviceID,
            epoch: pairingEpoch,
            generation: candidate,
            wasRevoked: revokedDevices.contains(deviceID)
        )
        return commitRepair(snapshot)
    }

    mutating func revoke(deviceID: UUID) -> [UUID] {
        revokedDevices.insert(deviceID)
        deviceEpochs[deviceID, default: 0] &+= 1
        let affected = authenticatedDevices.compactMap { $0.value == deviceID ? $0.key : nil }
        affected.forEach { authenticatedDevices[$0] = nil }
        return affected.sorted { $0.uuidString < $1.uuidString }
    }

    mutating func end(sessionID: UUID) -> Bool {
        let wasAuthenticated = authenticatedDevices.removeValue(forKey: sessionID) != nil
        let wasPending = pendingSessions.remove(sessionID) != nil
        return wasAuthenticated || wasPending
    }

    mutating func stop() -> [UUID] {
        generation &+= 1
        phase = .stopped
        let sessions = Set(pendingSessions).union(authenticatedDevices.keys)
        pendingSessions.removeAll()
        authenticatedDevices.removeAll()
        return sessions.sorted { $0.uuidString < $1.uuidString }
    }

    mutating func fail(generation candidate: UInt64) -> [UUID] {
        guard candidate == generation else { return [] }
        switch phase {
        case let .starting(active) where active == candidate:
            return stop()
        case let .listening(active) where active == candidate:
            return stop()
        default:
            return []
        }
    }
}
