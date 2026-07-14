import Foundation
import RemoteCore

public struct RemoteFrameCodec: Sendable {
    private static let protocolMaximumPayloadSize = 4 * 1_024 * 1_024

    private let maximumPayloadSize: Int
    private var buffer = Data()

    var bufferedByteCount: Int { buffer.count }

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
        var messages: [RemoteMessage] = []

        for byte in bytes {
            buffer.append(byte)

            guard buffer.count >= MemoryLayout<UInt32>.size else { continue }

            let payloadSize = buffer.prefix(MemoryLayout<UInt32>.size).reduce(0) { result, byte in
                (result << 8) | Int(byte)
            }
            guard payloadSize <= maximumPayloadSize else {
                throw Self.invalidFrame("Frame payload exceeds the allowed size.")
            }

            let frameSize = MemoryLayout<UInt32>.size + payloadSize
            guard buffer.count == frameSize else { continue }

            let payloadStart = buffer.index(buffer.startIndex, offsetBy: MemoryLayout<UInt32>.size)
            let payloadEnd = buffer.index(buffer.startIndex, offsetBy: frameSize)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            do {
                messages.append(try JSONDecoder().decode(RemoteMessage.self, from: payload))
            } catch {
                throw Self.invalidFrame("Frame payload could not be decoded.")
            }
            buffer.removeAll(keepingCapacity: true)
        }

        return messages
    }

    private static func invalidFrame(_ message: String) -> RemoteProtocolError {
        RemoteProtocolError(code: .invalidFrame, message: message)
    }
}
