public enum RemotePairingTeardownPhase: Equatable, Sendable {
    case provisional
    case committing
    case authenticated
    case other
}

public enum RemotePairingTeardownAction: Equatable, Sendable {
    case preserveDurablePreparedTransaction
    case performNormalCleanup
}

public enum RemotePairingTeardownPolicy {
    public static func action(for phase: RemotePairingTeardownPhase) -> RemotePairingTeardownAction {
        phase == .provisional ? .preserveDurablePreparedTransaction : .performNormalCleanup
    }
}
