/// Authorization for the exact topology, recovery policy and per-screen intent at effect submission.
public struct BrightnessWriteAuthorization: Equatable, Sendable {
    public let topology: UInt64
    public let recovery: UInt64
    public let intent: UInt64
    public init(topology: UInt64, recovery: UInt64, intent: UInt64) {
        self.topology = topology; self.recovery = recovery; self.intent = intent
    }
}

/// Applies software output only if the asynchronous hardware step still belongs to current intent.
@MainActor
public final class BrightnessOutputWriter {
    private let hardware: @MainActor (UInt32, Double) async -> Bool
    private let software: @MainActor (UInt32, Double) -> Bool
    private let authorization: @MainActor (UInt32) -> BrightnessWriteAuthorization?
    public init(hardware: @escaping @MainActor (UInt32, Double) async -> Bool,
                software: @escaping @MainActor (UInt32, Double) -> Bool,
                authorization: @escaping @MainActor (UInt32) -> BrightnessWriteAuthorization?) {
        self.hardware = hardware; self.software = software; self.authorization = authorization
    }
    public func apply(id: UInt32, output: BrightnessOutput) async -> Bool {
        guard let submitted = authorization(id), !Task.isCancelled else { return false }
        if let value = output.hardware, await !hardware(id, value) { return false }
        guard !Task.isCancelled, authorization(id) == submitted else { return false }
        return software(id, output.software)
    }
}
