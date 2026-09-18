//
//  PrivilegedOperationClient.swift
//  OnlySwitch
//

import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import ServiceManagement

@DependencyClient
struct PrivilegedOperationClient: Sendable {
    var status: @Sendable () async -> PrivilegedHelperStatus = { .unavailable }
    var installFromInteractiveUI: @Sendable () async throws -> Void = {
        throw PrivilegedOperationClientError.unavailable
    }
    var removeFromInteractiveUI: @Sendable () async throws -> Void = {
        throw PrivilegedOperationClientError.unavailable
    }
    var perform: @Sendable (PrivilegedOperation, Bool) async throws -> Void = { _, _ in
        throw PrivilegedOperationClientError.unavailable
    }
    var openSystemSettings: @Sendable () async -> Void = {}
}

enum PrivilegedOperationClientError: Error, Sendable, Equatable {
    case notInstalled
    case requiresApproval
    case disabled
    case unavailable
    case connectionInterrupted
    case connectionInvalidated
    case requestTimedOut
    case helperRejected
    case operationFailed
}

extension PrivilegedOperationClient: DependencyKey, TestDependencyKey {
    static var liveValue: Self { .live }

    static var testValue: Self {
        Self(
            status: unimplemented("\(Self.self).status"),
            installFromInteractiveUI: unimplemented("\(Self.self).installFromInteractiveUI"),
            removeFromInteractiveUI: unimplemented("\(Self.self).removeFromInteractiveUI"),
            perform: unimplemented("\(Self.self).perform"),
            openSystemSettings: unimplemented("\(Self.self).openSystemSettings")
        )
    }
}

extension DependencyValues {
    var privilegedOperationClient: PrivilegedOperationClient {
        get { self[PrivilegedOperationClient.self] }
        set { self[PrivilegedOperationClient.self] = newValue }
    }
}

extension PrivilegedOperationClient {
    static var live: Self {
        Self(
            status: {
                PrivilegedHelperStatus(serviceStatus: helperServiceStatus())
            },
            installFromInteractiveUI: {
                try helperService().register()
            },
            removeFromInteractiveUI: {
                try helperService().unregister()
            },
            perform: { operation, enabled in
                let status = PrivilegedHelperStatus(serviceStatus: helperServiceStatus())
                try status.requireEnabled()
                try await PrivilegedOperationXPCBridge.perform(operation, enabled: enabled)
            },
            openSystemSettings: {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
                    return
                }
                await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}

private extension PrivilegedHelperStatus {
    func requireEnabled() throws {
        switch self {
        case .enabled:
            return
        case .notInstalled:
            throw PrivilegedOperationClientError.notInstalled
        case .requiresApproval:
            throw PrivilegedOperationClientError.requiresApproval
        case .disabled:
            throw PrivilegedOperationClientError.disabled
        case .unavailable:
            throw PrivilegedOperationClientError.unavailable
        }
    }
}

private let privilegedHelperPlistName = "com.jacklandrin.OnlySwitch.PrivilegedHelper.plist"
private let privilegedHelperMachService = "com.jacklandrin.OnlySwitch.PrivilegedHelper"

private func helperService() -> SMAppService {
    SMAppService.daemon(plistName: privilegedHelperPlistName)
}

private func helperServiceStatus() -> PrivilegedHelperServiceStatus {
    switch helperService().status {
    case .notRegistered:
        .notRegistered
    case .enabled:
        .enabled
    case .requiresApproval:
        .requiresApproval
    case .notFound:
        .notFound
    @unknown default:
        .unknown
    }
}

private enum PrivilegedOperationXPCBridge {
    static func perform(_ operation: PrivilegedOperation, enabled: Bool) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let request = PrivilegedOperationXPCRequest(
                connection: NSXPCConnection(
                    machServiceName: privilegedHelperMachService,
                    options: .privileged
                )
            )

            group.addTask {
                try await request.perform(operation, enabled: enabled)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw PrivilegedOperationClientError.requestTimedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else { return }
            return result
        }
    }
}

/// Owns one XPC request and serializes every terminal event through an actor.
/// A fresh instance is intentionally used per operation so a stale daemon
/// connection cannot be reused after interruption or cancellation.
private actor PrivilegedOperationXPCRequest {
    private let connection: NSXPCConnection
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasFinished = false

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func perform(_ operation: PrivilegedOperation, enabled: Bool) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.start(operation, enabled: enabled, continuation: continuation)
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func start(
        _ operation: PrivilegedOperation,
        enabled: Bool,
        continuation: CheckedContinuation<Void, Error>
    ) {
        guard !hasFinished else {
            continuation.resume(throwing: PrivilegedOperationClientError.connectionInvalidated)
            return
        }

        self.continuation = continuation
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedOperationXPC.self)
        connection.interruptionHandler = { [weak self] in
            Task { await self?.fail(PrivilegedOperationClientError.connectionInterrupted) }
        }
        connection.invalidationHandler = { [weak self] in
            Task { await self?.fail(PrivilegedOperationClientError.connectionInvalidated) }
        }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] (_: Error) in
            Task { await self?.fail(PrivilegedOperationClientError.connectionInvalidated) }
        }) as? PrivilegedOperationXPC else {
            fail(PrivilegedOperationClientError.connectionInvalidated)
            return
        }

        proxy.setOperation(operation.rawValue, enabled: enabled) { [weak self] error in
            if let error {
                let clientError = Self.mapHelperError(error)
                Task { await self?.fail(clientError) }
            } else {
                Task { await self?.succeed() }
            }
        }
    }

    private func cancel() {
        fail(CancellationError())
    }

    private func succeed() {
        finish(.success(()))
    }

    private func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        connection.invalidate()
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func mapHelperError(_ error: NSError) -> PrivilegedOperationClientError {
        error.code == PrivilegedOperationError.unsupportedOperation.rawValue
            ? .helperRejected
            : .operationFailed
    }
}
