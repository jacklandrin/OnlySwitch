import Foundation
import RemoteCore

public enum RemoteWirePacket: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case plaintext, encrypted }

    case plaintext(RemoteMessage)
    case encrypted(RemoteEncryptedFrame)

    public var kind: Kind {
        switch self {
        case .plaintext: .plaintext
        case .encrypted: .encrypted
        }
    }

    public var plaintext: RemoteMessage? {
        guard case let .plaintext(message) = self else { return nil }
        return message
    }

    public var encrypted: RemoteEncryptedFrame? {
        guard case let .encrypted(frame) = self else { return nil }
        return frame
    }
}

public struct RemoteWireFrame: Equatable, Sendable {
    public let sequence: UInt64
    public let packet: RemoteWirePacket

    public init(sequence: UInt64, packet: RemoteWirePacket) {
        self.sequence = sequence
        self.packet = packet
    }
}

public struct RemoteWireSequenceValidator: Sendable {
    private var expectedSequence: UInt64?

    public init(expectedSequence: UInt64 = 0) {
        self.expectedSequence = expectedSequence
    }

    public mutating func accept(_ sequence: UInt64) throws {
        guard let expectedSequence, sequence == expectedSequence else {
            throw RemoteProtocolError(code: .replayDetected, message: "Wire frame sequence is not contiguous.")
        }
        self.expectedSequence = sequence == UInt64.max ? nil : sequence + 1
    }
}

public struct RemoteFrameCodec: Sendable {
    /// Wire header layout: version (1 byte), packet type (1 byte), reserved zeroes
    /// (2 bytes), payload length (4-byte big endian), and sequence (8-byte big endian).
    public static let headerSize = 16
    public static let protocolVersion: UInt8 = 1
    public static let protocolMaximumPayloadSize = 4 * 1_024 * 1_024

    private enum PacketType: UInt8 {
        case plaintext = 1
        case encrypted = 2
    }

    private let maximumPayloadSize: Int
    private var buffer = Data()

    public var bufferedByteCount: Int { buffer.count }

    public init(maximumPayloadSize: Int = Self.protocolMaximumPayloadSize) {
        self.maximumPayloadSize = min(max(0, maximumPayloadSize), Self.protocolMaximumPayloadSize)
    }

    public func encode(_ packet: RemoteWirePacket, sequence: UInt64) throws -> Data {
        let packetType: PacketType
        let payload: Data
        switch packet {
        case let .plaintext(message):
            packetType = .plaintext
            payload = try Self.encodePayload(message)
        case let .encrypted(frame):
            packetType = .encrypted
            payload = try Self.encodePayload(frame)
        }
        guard payload.count <= maximumPayloadSize else {
            throw Self.invalidFrame("Frame payload exceeds the allowed size.")
        }

        var result = Data([Self.protocolVersion, packetType.rawValue, 0, 0])
        result.appendBigEndian(UInt32(payload.count))
        result.appendBigEndian(sequence)
        result.append(payload)
        return result
    }

    public mutating func append<Bytes: DataProtocol>(_ bytes: Bytes) throws -> [RemoteWireFrame] {
        var frames: [RemoteWireFrame] = []

        for byte in bytes {
            buffer.append(byte)
            guard buffer.count >= Self.headerSize else { continue }

            let header = buffer.prefix(Self.headerSize)
            guard header[header.startIndex] == Self.protocolVersion else {
                throw Self.invalidFrame("Unsupported wire protocol version.")
            }
            let typeIndex = header.index(after: header.startIndex)
            guard let packetType = PacketType(rawValue: header[typeIndex]) else {
                throw Self.invalidFrame("Unknown wire packet type.")
            }
            let reservedStart = header.index(typeIndex, offsetBy: 1)
            guard header[reservedStart] == 0, header[header.index(after: reservedStart)] == 0 else {
                throw Self.invalidFrame("Reserved wire header bytes must be zero.")
            }

            let payloadSize = Int(Self.readBigEndianUInt32(header, offset: 4))
            guard payloadSize <= maximumPayloadSize else {
                throw Self.invalidFrame("Frame payload exceeds the allowed size.")
            }
            let frameSize = Self.headerSize + payloadSize
            guard buffer.count == frameSize else { continue }

            let sequence = Self.readBigEndianUInt64(header, offset: 8)
            let payload = Data(buffer.dropFirst(Self.headerSize))
            let packet: RemoteWirePacket
            do {
                switch packetType {
                case .plaintext:
                    packet = .plaintext(try JSONDecoder().decode(RemoteMessage.self, from: payload))
                case .encrypted:
                    packet = .encrypted(try JSONDecoder().decode(RemoteEncryptedFrame.self, from: payload))
                }
            } catch {
                throw Self.invalidFrame("Frame payload could not be decoded.")
            }
            frames.append(RemoteWireFrame(sequence: sequence, packet: packet))
            buffer.removeAll(keepingCapacity: true)
        }

        return frames
    }

    private static func readBigEndianUInt32(_ bytes: Data.SubSequence, offset: Int) -> UInt32 {
        bytes.dropFirst(offset).prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func encodePayload<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func readBigEndianUInt64(_ bytes: Data.SubSequence, offset: Int) -> UInt64 {
        bytes.dropFirst(offset).prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func invalidFrame(_ message: String) -> RemoteProtocolError {
        RemoteProtocolError(code: .invalidFrame, message: message)
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.bigEndian
        append(Swift.withUnsafeBytes(of: &value) { Data($0) })
    }
}
