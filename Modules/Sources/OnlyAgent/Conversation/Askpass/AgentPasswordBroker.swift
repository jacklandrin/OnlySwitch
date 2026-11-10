//
//  AgentPasswordBroker.swift
//  Modules
//

import Foundation

/// Connects a running step's password prompt with the answer typed in the UI.
actor AgentPasswordBroker {
    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]

    /// Announces a request and waits for `answer(_:password:)`.
    func request(
        prompt: String,
        announce: @Sendable (AgentPasswordRequest) -> Void
    ) async -> String? {
        let request = AgentPasswordRequest(id: UUID(), prompt: prompt)
        return await withCheckedContinuation { continuation in
            pending[request.id] = continuation
            announce(request)
        }
    }

    func answer(_ id: UUID, password: String?) {
        pending.removeValue(forKey: id)?.resume(returning: password)
    }
}
