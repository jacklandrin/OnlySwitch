import Foundation
import Testing
@testable import RemoteCore
@testable import RemoteTransport

struct RemoteFrameCodecTests {
    @Test func plaintextFrameHasStableGoldenHeaderAndPayload() throws {
        let packet = RemoteWirePacket.plaintext(.ping(42))
        let frame = try RemoteFrameCodec().encode(packet, sequence: 7)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(RemoteMessage.ping(42))

        var expected = Data([1, 1, 0, 0])
        expected.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        expected.append(contentsOf: UInt64(7).bigEndianBytes)
        expected.append(payload)

        #expect(frame == expected)
    }

    @Test func partialFrameWaitsForRemainder() throws {
        var codec = RemoteFrameCodec()
        let frame = try codec.encode(.plaintext(.ping(42)), sequence: 0)

        #expect(try codec.append(frame.prefix(15)).isEmpty)
        #expect(try codec.append(frame.dropFirst(15)) == [
            RemoteWireFrame(sequence: 0, packet: .plaintext(.ping(42)))
        ])
    }

    @Test func combinedPacketKindsDecodeInOrder() throws {
        var codec = RemoteFrameCodec()
        let encrypted = RemoteEncryptedFrame(noncePrefix: 9, counter: 3, ciphertext: Data([1, 2, 3]))
        let data = try codec.encode(.plaintext(.ping(1)), sequence: 10)
            + codec.encode(.encrypted(encrypted), sequence: 11)

        #expect(try codec.append(data) == [
            RemoteWireFrame(sequence: 10, packet: .plaintext(.ping(1))),
            RemoteWireFrame(sequence: 11, packet: .encrypted(encrypted))
        ])
    }

    @Test func unsupportedVersionIsRejectedAtHeaderBoundary() throws {
        var codec = RemoteFrameCodec()
        let header = Data([2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        #expect(throws: RemoteProtocolError.self) { try codec.append(header) }
        #expect(codec.bufferedByteCount <= RemoteFrameCodec.headerSize)
    }

    @Test func unknownPacketTypeIsRejectedAtHeaderBoundary() throws {
        var codec = RemoteFrameCodec()
        let header = Data([1, 99, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        #expect(throws: RemoteProtocolError.self) { try codec.append(header) }
    }

    @Test func nonzeroReservedHeaderIsRejected() throws {
        var codec = RemoteFrameCodec()
        let header = Data([1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        #expect(throws: RemoteProtocolError.self) { try codec.append(header) }
    }

    @Test func oversizedHeaderRejectsBeforeRetainingBody() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 8)
        var input = Data([1, 1, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0])
        input.append(Data(repeating: 0xAA, count: 1_024 * 1_024))

        #expect(throws: RemoteProtocolError.self) { try codec.append(input) }
        #expect(codec.bufferedByteCount <= RemoteFrameCodec.headerSize)
    }

    @Test func malformedPayloadIsRejectedForDeclaredType() throws {
        var codec = RemoteFrameCodec()
        var frame = Data([1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        frame.append(0xFF)

        #expect(throws: RemoteProtocolError.self) { try codec.append(frame) }
    }

    @Test func sequenceValidatorRequiresContiguousFramesStartingAtZero() throws {
        var validator = RemoteWireSequenceValidator()

        try validator.accept(0)
        try validator.accept(1)
        #expect(throws: RemoteProtocolError.self) { try validator.accept(1) }
        #expect(throws: RemoteProtocolError.self) { try validator.accept(3) }
    }

    @Test func sequenceValidatorRejectsFramesAfterMaximumSequence() throws {
        var validator = RemoteWireSequenceValidator(expectedSequence: UInt64.max)

        try validator.accept(UInt64.max)
        #expect(throws: RemoteProtocolError.self) { try validator.accept(0) }
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
