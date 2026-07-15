import Foundation

struct RemoteHostConfiguration: Equatable, Sendable {
    var displayName: String
    var serviceType = "_onlyswitch._tcp"
    var port: UInt16 = 0
}

struct PairingWindow: Equatable, Sendable {
    let code: String
    let expiresAt: Date
}

enum HostStatus: Equatable, Sendable {
    case stopped
    case starting
    case listening(port: UInt16)
    case failed(String)
}

enum RemoteHostEvent: Equatable, Sendable {
    case statusChanged(HostStatus)
    case pairingChanged(PairingWindow?)
    case devicesChanged([PairedRemoteDevice])
    case connectionCountChanged(Int)
}
