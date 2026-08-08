import Foundation
import OnlyControl
import RemoteCore
import Switches

@MainActor
final class RemoteCommandRouter: Sendable {
    private let resolveBuiltIn: @MainActor @Sendable (UInt64) -> SwitchProvider?
    private let installedShortcutNames: @MainActor @Sendable () async -> Set<String>
    private let runShortcut: @MainActor @Sendable (String) async throws -> Void
    private let resolveEvolution: @MainActor @Sendable (UUID) -> EvolutionItem?
    private let runEvolution: @MainActor @Sendable (EvolutionItem, RemoteControlAction) async throws -> Void
    private let cache: RecentRequestCache
    private var inFlight: [UUID: Task<RemoteActionResult, Never>] = [:]

    init(
        resolveBuiltIn: @escaping @MainActor @Sendable (UInt64) -> SwitchProvider?,
        installedShortcutNames: @escaping @MainActor @Sendable () async -> Set<String> = { [] },
        runShortcut: @escaping @MainActor @Sendable (String) async throws -> Void = { _ in
            throw RemoteProtocolError(
                code: .actionNotSupported,
                message: "Shortcut actions are unavailable"
            )
        },
        resolveEvolution: @escaping @MainActor @Sendable (UUID) -> EvolutionItem? = { _ in nil },
        runEvolution: @escaping @MainActor @Sendable (
            EvolutionItem,
            RemoteControlAction
        ) async throws -> Void = { _, _ in
            throw RemoteProtocolError(
                code: .actionNotSupported,
                message: "Evolution actions are unavailable"
            )
        },
        cache: RecentRequestCache = .init(capacity: 512)
    ) {
        self.resolveBuiltIn = resolveBuiltIn
        self.installedShortcutNames = installedShortcutNames
        self.runShortcut = runShortcut
        self.resolveEvolution = resolveEvolution
        self.runEvolution = runEvolution
        self.cache = cache
    }

    func perform(_ request: RemoteActionRequest) async -> RemoteActionResult {
        if let cached = await cache.result(for: request.requestID) {
            return cached
        }
        if let task = inFlight[request.requestID] {
            return await task.value
        }

        let task = Task { @MainActor [self] in
            await execute(request)
        }
        inFlight[request.requestID] = task
        let result = await task.value
        await cache.insert(result, for: request.requestID)
        inFlight[request.requestID] = nil
        return result
    }

    private func execute(_ request: RemoteActionRequest) async -> RemoteActionResult {
        do {
            let status = try await executeAction(request)
            return .init(requestID: request.requestID, result: .success(status))
        } catch let error as RemoteProtocolError {
            return .init(requestID: request.requestID, result: .failure(error))
        } catch {
            return .init(
                requestID: request.requestID,
                result: .failure(.init(code: .executionFailed, message: "The control could not be executed"))
            )
        }
    }

    private func executeAction(_ request: RemoteActionRequest) async throws -> RemoteControlStatus? {
        switch request.controlID.kind {
        case .builtIn:
            return try await executeBuiltIn(request)
        case .shortcut:
            guard case .trigger = request.action else {
                throw actionNotSupported()
            }
            guard await installedShortcutNames().contains(request.controlID.value) else {
                throw controlNotFound("Shortcut not found")
            }
            try await runShortcut(request.controlID.value)
            return nil
        case .evolution:
            guard let id = UUID(uuidString: request.controlID.value),
                  id.uuidString == request.controlID.value,
                  let evolution = resolveEvolution(id) else {
                throw controlNotFound("Evolution not found")
            }
            let availability = RemoteCatalogProvider.availability(for: evolution)
            guard availability.isAvailable else {
                throw RemoteProtocolError(
                    code: .controlUnavailable,
                    message: availability.reason ?? "Evolution unavailable"
                )
            }
            try validate(action: request.action, for: evolution.controlType)
            try await runEvolution(evolution, request.action)
            return nil
        }
    }

    private func executeBuiltIn(_ request: RemoteActionRequest) async throws -> RemoteControlStatus {
        guard let rawValue = UInt64(request.controlID.value),
              String(rawValue) == request.controlID.value,
              let type = SwitchType(rawValue: rawValue),
              let control = resolveBuiltIn(rawValue),
              control.type == type else {
            throw controlNotFound("Control not found")
        }

        let availability = RemoteCatalogProvider.availability(for: type, control: control)
        guard availability.isAvailable else {
            throw RemoteProtocolError(
                code: .controlUnavailable,
                message: availability.reason ?? "Control unavailable"
            )
        }
        try validate(action: request.action, for: type.barInfo().controlType)

        switch request.action {
        case let .setState(isOn):
            try await control.operateSwitch(isOn: isOn)
        case .trigger:
            try await control.operateSwitch(isOn: true)
        }

        let controlType = type.barInfo().controlType
        let info = await control.currentInfo()
        return RemoteControlStatus(
            id: request.controlID,
            isAvailable: true,
            unavailableReason: nil,
            isOn: controlType == .Button ? nil : await control.currentStatus(),
            secondaryInformation: ControlItemSecondaryInformation.subtitle(
                info: info,
                isAirPods: type == .airPods
            ),
            isProcessing: false,
            revision: 0,
            updatedAt: Date()
        )
    }

    private func validate(action: RemoteControlAction, for controlType: ControlType) throws {
        switch (controlType, action) {
        case (.Button, .trigger), (.Switch, .setState), (.Player, .setState):
            return
        default:
            throw actionNotSupported()
        }
    }

    private func actionNotSupported() -> RemoteProtocolError {
        .init(code: .actionNotSupported, message: "This action is not supported by the control")
    }

    private func controlNotFound(_ message: String) -> RemoteProtocolError {
        .init(code: .controlNotFound, message: message)
    }
}
