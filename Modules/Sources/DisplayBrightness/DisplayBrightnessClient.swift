import Dependencies
import Foundation

/// The app injects native/DDC/shade effects; package views never access system services.
public struct DisplayBrightnessClient: Sendable {
    public var scan: @Sendable () async throws -> BrightnessSnapshot
    public var apply: @Sendable (BrightnessRequest) async throws -> Void
    public var events: @Sendable () async -> AsyncStream<BrightnessSnapshot>
    public var loadSettings: @Sendable () async -> BrightnessSettings
    public var saveSettings: @Sendable (BrightnessSettings) async throws -> Void
    public var requestKeyboardAccess: @Sendable () async -> Void
    public var resetSoftwareDimming: @Sendable () async -> Void

    public init(
        scan: @escaping @Sendable () async throws -> BrightnessSnapshot,
        apply: @escaping @Sendable (BrightnessRequest) async throws -> Void,
        events: @escaping @Sendable () async -> AsyncStream<BrightnessSnapshot>,
        loadSettings: @escaping @Sendable () async -> BrightnessSettings,
        saveSettings: @escaping @Sendable (BrightnessSettings) async throws -> Void,
        resetSoftwareDimming: @escaping @Sendable () async -> Void,
        requestKeyboardAccess: @escaping @Sendable () async -> Void = {}
    ) {
        self.scan = scan
        self.apply = apply
        self.events = events
        self.loadSettings = loadSettings
        self.saveSettings = saveSettings
        self.requestKeyboardAccess = requestKeyboardAccess
        self.resetSoftwareDimming = resetSoftwareDimming
    }
}

extension DisplayBrightnessClient: DependencyKey {
    public static let liveValue = Self(
        scan: { .init() }, apply: { _ in throw BrightnessError.unavailable },
        events: { AsyncStream { $0.finish() } }, loadSettings: { .init() },
        saveSettings: { _ in throw BrightnessError.unavailable }, resetSoftwareDimming: {}
    )
    public static let testValue = Self(
        scan: { .init() }, apply: { _ in }, events: { AsyncStream { $0.finish() } },
        loadSettings: { .init() }, saveSettings: { _ in }, resetSoftwareDimming: {}
    )
}

public extension DependencyValues {
    var displayBrightnessClient: DisplayBrightnessClient {
        get { self[DisplayBrightnessClient.self] }
        set { self[DisplayBrightnessClient.self] = newValue }
    }
}
