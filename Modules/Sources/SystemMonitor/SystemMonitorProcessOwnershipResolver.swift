import RemoteCore

public enum SystemMonitorProcessActivationOutcome: Equatable, Sendable {
    case activated
    case unavailable
}

@MainActor
public struct SystemMonitorProcessOwnershipResolver {
    private let processIdentity: @MainActor @Sendable (Int32) -> SystemMonitorProcessIdentity?
    private let regularApplicationIdentity: @MainActor @Sendable (Int32) -> SystemMonitorProcessIdentity?
    private let responsiblePID: @MainActor @Sendable (Int32) -> Int32?
    private let parentPID: @MainActor @Sendable (Int32) -> Int32?

    public init(
        processIdentity: @escaping @MainActor @Sendable (Int32) -> SystemMonitorProcessIdentity?,
        regularApplicationIdentity: @escaping @MainActor @Sendable (Int32) -> SystemMonitorProcessIdentity?,
        responsiblePID: @escaping @MainActor @Sendable (Int32) -> Int32?,
        parentPID: @escaping @MainActor @Sendable (Int32) -> Int32?
    ) {
        self.processIdentity = processIdentity
        self.regularApplicationIdentity = regularApplicationIdentity
        self.responsiblePID = responsiblePID
        self.parentPID = parentPID
    }

    public nonisolated static func startTimeMicroseconds(
        seconds: Int64,
        microseconds: Int32
    ) -> UInt64? {
        guard seconds >= 0, (0 ..< 1_000_000).contains(microseconds) else { return nil }
        let (wholeMicroseconds, overflow) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000)
        guard !overflow else { return nil }
        let (result, additionOverflow) = wholeMicroseconds.addingReportingOverflow(UInt64(microseconds))
        return additionOverflow ? nil : result
    }

    public func activationTarget(
        for sampledProcess: SystemMonitorProcessIdentity
    ) -> SystemMonitorProcessActivationTarget? {
        guard processIdentity(sampledProcess.pid) == sampledProcess else { return nil }

        if regularApplicationIdentity(sampledProcess.pid) == sampledProcess {
            return .init(sampledProcess: sampledProcess, owningApplication: sampledProcess)
        }

        if let responsiblePID = responsiblePID(sampledProcess.pid),
           responsiblePID != sampledProcess.pid,
           let owner = regularApplicationIdentity(responsiblePID) {
            return .init(sampledProcess: sampledProcess, owningApplication: owner)
        }

        var visited: Set<Int32> = [sampledProcess.pid]
        var currentPID = sampledProcess.pid
        for _ in 0 ..< 4 {
            guard let candidate = parentPID(currentPID),
                  candidate > 0,
                  visited.insert(candidate).inserted else { return nil }
            if let owner = regularApplicationIdentity(candidate) {
                return .init(sampledProcess: sampledProcess, owningApplication: owner)
            }
            currentPID = candidate
        }
        return nil
    }

    public func activate(
        _ target: SystemMonitorProcessActivationTarget,
        using activation: @MainActor @Sendable (Int32) -> Bool
    ) -> SystemMonitorProcessActivationOutcome {
        guard processIdentity(target.sampledProcess.pid) == target.sampledProcess,
              processIdentity(target.owningApplication.pid) == target.owningApplication,
              regularApplicationIdentity(target.owningApplication.pid) == target.owningApplication,
              activation(target.owningApplication.pid) else {
            return .unavailable
        }
        return .activated
    }
}
