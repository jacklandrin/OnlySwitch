public struct RemoteProtocolError: Codable, Error, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case upgradeRequired
        case authenticationFailed
        case pairingExpired
        case pairingRateLimited
        case controlNotFound
        case controlUnavailable
        case actionNotSupported
        case executionFailed
        case requestTimedOut
        case invalidFrame
        case replayDetected
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}
