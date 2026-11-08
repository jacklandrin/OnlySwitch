import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    static func validatedDeviceName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.utf8.count <= 128,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid device name")
        }
        return trimmed
    }

    static func validateCatalog(_ catalog: RemoteCatalogCache, minimumRevision: UInt64) throws {
        guard catalog.revision >= minimumRevision,
              catalog.controls.count <= 4_096,
              Set(catalog.controls.map(\.id)).count == catalog.controls.count else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog snapshot")
        }
        for descriptor in catalog.controls {
            guard descriptor.id.value.isEmpty == false,
                  descriptor.id.value.utf8.count <= 512,
                  descriptor.title.isEmpty == false,
                  descriptor.title.utf8.count <= 512,
                  (descriptor.unavailableReason?.utf8.count ?? 0) <= 1_024 else {
                throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog descriptor")
            }
            switch descriptor.icon {
            case let .systemSymbol(name):
                guard name.isEmpty == false, name.utf8.count <= 256 else {
                    throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog icon")
                }
            case let .png(data):
                guard data.count <= 256 * 1_024 else {
                    throw RemoteProtocolError(code: .invalidFrame, message: "Catalog icon exceeds 256 KiB")
                }
            }
        }
    }

    static func orderedCandidates(
        _ candidates: [DiscoveredMac],
        preferredEndpointDescription: String? = nil
    ) -> [DiscoveredMac] {
        candidates.sorted { lhs, rhs in
            let left = String(describing: lhs.endpoint)
            let right = String(describing: rhs.endpoint)
            if left == preferredEndpointDescription { return right != preferredEndpointDescription }
            if right == preferredEndpointDescription { return false }
            return left < right
        }
    }

    static func boundedCandidates(
        _ candidates: [DiscoveredMac],
        preferredEndpoints: [UUID: String] = [:],
        selectedMacID: UUID? = nil
    ) -> [UUID: [String: DiscoveredMac]] {
        let grouped = Dictionary(grouping: candidates, by: \.id)
        var queues: [UUID: [(String, DiscoveredMac)]] = [:]
        for id in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let preferred = preferredEndpoints[id]
            var unique: [String: DiscoveredMac] = [:]
            for candidate in orderedCandidates(grouped[id] ?? [], preferredEndpointDescription: preferred) {
                unique[String(describing: candidate.endpoint)] = candidate
            }
            queues[id] = orderedCandidates(Array(unique.values), preferredEndpointDescription: preferred)
                .prefix(maximumCandidatesPerMac)
                .map { (String(describing: $0.endpoint), $0) }
        }
        var result: [UUID: [String: DiscoveredMac]] = [:]
        var remainingCapacity = maximumCandidatesGlobally
        if let selectedMacID, let selectedQueue = queues[selectedMacID] {
            for (description, candidate) in selectedQueue.prefix(remainingCapacity) {
                result[selectedMacID, default: [:]][description] = candidate
                remainingCapacity -= 1
            }
            queues[selectedMacID] = []
        }
        let ids = queues.keys.sorted { $0.uuidString < $1.uuidString }
        var rank = 0
        while remainingCapacity > 0 {
            var inserted = false
            for id in ids where remainingCapacity > 0 {
                guard let queue = queues[id], rank < queue.count else { continue }
                let (description, candidate) = queue[rank]
                result[id, default: [:]][description] = candidate
                remainingCapacity -= 1
                inserted = true
            }
            guard inserted else { break }
            rank += 1
        }
        return result
    }

    static func candidateSetChanged(
        previous: [String: DiscoveredMac],
        updated: [String: DiscoveredMac]
    ) -> Bool {
        Set(previous.keys) != Set(updated.keys)
    }

    func installDiscoveredCandidatesForTesting(_ candidates: [DiscoveredMac]) {
        discovered = Self.boundedCandidates(
            candidates,
            selectedMacID: selected?.id
        )
    }

    var lifecycleSnapshot: (foregrounded: Bool, ownsBrowser: Bool, hasConnectionTask: Bool, hasRetryTask: Bool) {
        (foregrounded, browser != nil, connectionTask != nil, browserRetryTask != nil)
    }

    static func isCurrentSession(
        selectedMacID: UUID?,
        currentToken: UUID?,
        eventMacID: UUID,
        eventToken: UUID
    ) -> Bool {
        selectedMacID == eventMacID && currentToken == eventToken
    }

    static func shouldClearSession(currentToken: UUID?, failedToken: UUID) -> Bool {
        currentToken == failedToken
    }

    static func browserRetryDelay(failureCount: Int) -> Duration {
        let delays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        return delays[min(max(failureCount, 0), delays.count - 1)]
    }

    static func shouldRestartBrowser(after failure: DiscoveryFailure, failureCount: Int) -> Bool {
        switch failure {
        case .localNetworkAccessNeeded:
            failureCount == 0
        case .networkUnavailable, .browserUnavailable:
            true
        }
    }

    static func mayCommitPairing(
        activeToken: UUID?,
        candidateToken: UUID,
        currentGeneration: UInt64,
        expectedGeneration: UInt64,
        foregrounded: Bool
    ) -> Bool {
        foregrounded && activeToken == candidateToken && currentGeneration == expectedGeneration
    }

    static func isAuthoritativeRevocation(_ message: RemoteMessage) -> Bool {
        message == .credentialRevoked
    }

    static func safeMessage(_ error: Swift.Error) -> String? {
        if let error = error as? RemoteProtocolError { return error.message }
        return "Unable to connect to this Mac"
    }


    static func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw RemoteProtocolError(code: .requestTimedOut, message: "The Mac did not respond in time")
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
    }
}
