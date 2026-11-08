import Foundation
import RemoteCore
import RemoteTransport

extension RemoteHost {
    func activePairingWindow() -> PairingWindow? {
        guard let pairing, pairing.expiresAt > Date(), pairingFailures < 5 else {
            if self.pairing != nil {
                self.pairing = nil
                publish(.pairingChanged(nil))
            }
            return nil
        }
        return pairing
    }

    func pairingSnapshot(
        deviceID: UUID,
        generation: UInt64
    ) -> RemotePairingSnapshot? {
        lifecycle.pairingSnapshot(for: deviceID, generation: generation)
    }

    func validatePairing(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.validateRepair(snapshot)
    }

    func commitPairing(_ snapshot: RemotePairingSnapshot) async -> Bool {
        await commitStageReached(.duringLifecycleCommit)
        let committed = lifecycle.commitRepair(snapshot)
        await commitStageReached(.afterLifecycleCommit)
        return committed
    }

    func rollbackPairing(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.rollbackRepair(snapshot)
    }

    func recordPairingFailure() {
        pairingFailures += 1
        if pairingFailures >= 5 { cancelPairing() }
    }

    func consumePairing(code: String) -> Bool {
        guard let current = activePairingWindow(), current.code == code else { return false }
        cancelPairing()
        return true
    }

    func sessionAuthenticated(_ sessionID: UUID, deviceID: UUID, generation: UInt64) async -> Bool {
        authenticatedSessionObserver()
        guard lifecycle.mayAuthorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        ) else { return false }
        let credentialExists = (try? await credentialStore.load(deviceID)) != nil
        guard lifecycle.authorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation,
            credentialExists: credentialExists
        ) else { return false }
        return true
    }

    func sessionAuthenticationConfirmed(
        _ sessionID: UUID,
        deviceID: UUID,
        generation: UInt64
    ) async -> Bool {
        guard lifecycle.isAuthorized(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        ) else { return false }
        publish(.connectionCountChanged(lifecycle.authenticatedCount))
        await catalogMonitor.setAuthenticatedSessionCount(lifecycle.authenticatedCount)
        if let devices = try? await credentialStore.loadAll() {
            guard lifecycle.isAuthorized(
                sessionID: sessionID,
                deviceID: deviceID,
                generation: generation
            ) else { return false }
            publish(.devicesChanged(devices))
        }
        return lifecycle.isAuthorized(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        )
    }

    func sessionAuthenticationIsAuthorized(
        _ sessionID: UUID,
        deviceID: UUID,
        generation: UInt64
    ) -> Bool {
        lifecycle.isAuthorized(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        )
    }

    func sessionEnded(_ id: UUID) async {
        let previousCount = lifecycle.authenticatedCount
        _ = lifecycle.end(sessionID: id)
        sessions.removeValue(forKey: id)
        await statusScheduler.remove(sessionID: id)
        if lifecycle.authenticatedCount != previousCount {
            await catalogMonitor.setAuthenticatedSessionCount(lifecycle.authenticatedCount)
            publish(.connectionCountChanged(lifecycle.authenticatedCount))
        }
    }

    func evictSession(_ id: UUID) async {
        let previousCount = lifecycle.authenticatedCount
        _ = lifecycle.end(sessionID: id)
        let peer = sessions.removeValue(forKey: id)
        await statusScheduler.remove(sessionID: id)
        await peer?.close()
        if lifecycle.authenticatedCount != previousCount {
            await catalogMonitor.setAuthenticatedSessionCount(lifecycle.authenticatedCount)
            publish(.connectionCountChanged(lifecycle.authenticatedCount))
        }
    }
}
