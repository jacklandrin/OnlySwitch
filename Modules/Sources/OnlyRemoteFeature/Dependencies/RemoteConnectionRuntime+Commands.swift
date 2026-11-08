import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    func subscribe(_ ids: Set<RemoteControlID>) async throws {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        try await session.subscribe(ids)
    }

    func send(_ invocation: RemoteActionInvocation) async throws -> RemoteActionResult {
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              let session
        else { throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed") }
        let result = try await actionDeadline(actionTimeout) {
            try await session.send(invocation.request)
        }
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              self.session === session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        return result
    }

    func fetchCodexUsage(_ invocation: RemoteCodexUsageInvocation) async throws -> RemoteCodexUsageResult {
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        guard session.protocolVersion.supportsCodexUsageRemote else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on the selected Mac")
        }
        let result = try await Self.withTimeout(.seconds(45)) {
            try await session.fetchCodexUsage(invocation.request)
        }
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              self.session === session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        return result
    }

    func fetchClaudeUsage(_ invocation: RemoteClaudeUsageInvocation) async throws -> RemoteClaudeUsageResult {
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        guard session.protocolVersion.supportsClaudeUsageRemote else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on the selected Mac")
        }
        let result = try await Self.withTimeout(.seconds(45)) {
            try await session.fetchClaudeUsage(invocation.request)
        }
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              self.session === session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        return result
    }

    func sendSoundMixer(_ command: RemoteSoundMixerCommand) async throws {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        try await session.sendSoundMixer(command)
    }

    func setSystemMonitorStreaming(_ enabled: Bool) async throws {
        guard let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline")
        }
        try await session.setSystemMonitorStreaming(enabled)
    }

    func setSoundMixerStreaming(_ enabled: Bool) async throws {
        guard let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline")
        }
        try await session.setSoundMixerStreaming(enabled)
    }

    func setBrightnessStreaming(_ enabled: Bool) async throws {
        guard let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline")
        }
        try await session.setBrightnessStreaming(enabled)
    }

    func sendBrightness(_ command: RemoteBrightnessCommand) async throws {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        try await session.sendBrightness(command)
    }

    func setScreenshotsStreaming(_ enabled: Bool) async throws {
        guard let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline")
        }
        try await session.setScreenshotsStreaming(enabled)
    }

    func fetchScreenshotThumbnails(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotThumbnailsRequest>
    ) async throws -> RemoteScreenshotThumbnailsResult {
        try await screenshotRequest(invocation) { try await $0.fetchScreenshotThumbnails(invocation.request) }
    }

    func fetchScreenshotImage(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotImageRequest>
    ) async throws -> RemoteScreenshotImagePayload {
        // The delivered file belongs to the caller only once it is returned.
        try await screenshotRequest(invocation, discard: { try? FileManager.default.removeItem(at: $0.fileURL) }) {
            try await $0.fetchScreenshotImage(invocation.request)
        }
    }

    func deleteScreenshots(
        _ invocation: RemoteScreenshotInvocation<RemoteScreenshotDeleteRequest>
    ) async throws -> RemoteScreenshotDeleteResult {
        try await screenshotRequest(invocation) { try await $0.deleteScreenshots(invocation.request) }
    }

    /// Timeouts live in the session's `RemoteScreenshotResponses` (per reply, or per chunk for images).
    /// `discard` releases a result that is dropped because the session changed while it was in flight.
    private func screenshotRequest<Request: Equatable & Sendable, Value: Sendable>(
        _ invocation: RemoteScreenshotInvocation<Request>,
        discard: (Value) -> Void = { _ in },
        _ operation: @Sendable (RemoteClientSession) async throws -> Value
    ) async throws -> Value {
        guard selected?.id == invocation.macID, let session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        let result = try await operation(session)
        guard selected?.id == invocation.macID, self.session === session else {
            discard(result)
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        return result
    }
}
