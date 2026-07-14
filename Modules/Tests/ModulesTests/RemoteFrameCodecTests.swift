import Foundation
import Testing
@testable import RemoteCore
@testable import RemoteTransport

struct RemoteFrameCodecTests {
    @Test func partialFrameWaitsForRemainder() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 4 * 1_024 * 1_024)
        let frame = try codec.encode(.ping(42))

        #expect(try codec.append(frame.prefix(3)).isEmpty)
        #expect(try codec.append(frame.dropFirst(3)) == [.ping(42)])
    }

    @Test func combinedFramesDecodeInOrder() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 4 * 1_024 * 1_024)
        let data = try codec.encode(.ping(1)) + codec.encode(.pong(2))

        #expect(try codec.append(data) == [.ping(1), .pong(2)])
    }

    @Test func oversizedFrameIsRejectedBeforePayloadDecode() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 8)

        #expect(throws: RemoteProtocolError.self) {
            try codec.append(Data([0, 0, 0, 9]))
        }
    }

    @Test func oversizedHeaderRejectsBeforeRetainingBody() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 8)
        var input = Data([0, 0, 0, 9])
        input.append(Data(repeating: 0xAA, count: 1_024 * 1_024))

        #expect(throws: RemoteProtocolError.self) {
            try codec.append(input)
        }
        #expect(codec.bufferedByteCount <= MemoryLayout<UInt32>.size)
    }
}
