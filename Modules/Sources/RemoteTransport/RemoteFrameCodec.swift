import Foundation
import RemoteCore

public struct RemoteFrameCodec: Sendable {
    private static let protocolMaximumPayloadSize = 4 * 1_024 * 1_024

    private let maximumPayloadSize: Int
    private var buffer = Data()

    public init(maximumPayloadSize: Int = 4 * 1_024 * 1_024) {
        self.maximumPayloadSize = min(max(0, maximumPayloadSize), Self.protocolMaximumPayloadSize)
    }

    public func encode(_ message: RemoteMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maximumPayloadSize else {
            throw Self.invalidFrame("Frame payload exceeds the allowed size.")
        }

        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    public mutating func append<Bytes: DataProtocol>(_ bytes: Bytes) throws -> [RemoteMessage] {
        buffer.append(contentsOf: bytes)
        var messages: [RemoteMessage] = []

        while buffer.count >= MemoryLayout<UInt32>.size {
            let payloadSize = buffer.prefix(4).reduce(0) { partialResult, byte in
                (partialResult << 8) | Int(byte)
            }
            guard payloadSize <= maximumPayloadSize else {
                throw Self.invalidFrame("Frame payload exceeds the allowed size.")
            }

            let frameSize = 4 + payloadSize
            guard buffer.count >= frameSize else { break }

            let payloadStart = buffer.index(buffer.startIndex, offsetBy: 4)
            let payloadEnd = buffer.index(buffer.startIndex, offsetBy: frameSize)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            do {
                messages.append(try JSONDecoder().decode(RemoteMessage.self, from: payload))
            } catch {
                throw Self.invalidFrame("Frame payload could not be decoded.")
            }
            buffer.removeFirst(frameSize)
        }

        return messages
    }

    private static func invalidFrame(_ message: String) -> RemoteProtocolError {
        RemoteProtocolError(code: .invalidFrame, message: message)
    }
}
