//
//  PrivilegedAccessViewModel.swift
//  OnlySwitch
//

import Foundation

@MainActor
final class PrivilegedAccessViewModel: ObservableObject {
    @Published private(set) var status: PrivilegedHelperStatus = .unavailable
    @Published private(set) var presentation = PrivilegedAccessPresentation(status: .unavailable)
    @Published private(set) var isWorking = false
    @Published private(set) var messageKey: String?

    private let client: PrivilegedOperationClient

    init(client: PrivilegedOperationClient = .live) {
        self.client = client
    }

    func refresh() async {
        status = await client.status()
        presentation = .init(status: status)
    }

    func installOrRepair() async {
        await performLocalRegistration()
    }

    func remove() async {
        isWorking = true
        messageKey = nil
        do {
            try await client.removeFromInteractiveUI()
            messageKey = "Privileged access removed"
        } catch {
            messageKey = message(for: error)
        }
        isWorking = false
        await refresh()
    }

    func openSystemSettings() async {
        await client.openSystemSettings()
    }

    private func performLocalRegistration() async {
        isWorking = true
        messageKey = nil
        do {
            try await client.installFromInteractiveUI()
            messageKey = "Privileged access authorized"
        } catch {
            messageKey = message(for: error)
        }
        isWorking = false
        await refresh()
    }

    private func message(for error: Error) -> String {
        switch error as? PrivilegedOperationClientError {
        case .requiresApproval:
            "Authorization approval needed"
        case .disabled:
            "Privileged access disabled"
        case .notInstalled, .unavailable:
            "Privileged helper unavailable"
        case .operationFailed, .helperRejected, .connectionInterrupted,
             .connectionInvalidated, .requestTimedOut:
            "Privileged operation failed"
        case nil:
            "Privileged access could not be changed"
        }
    }
}
