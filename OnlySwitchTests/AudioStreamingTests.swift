import AVFoundation
import Foundation
import Testing
@testable import OnlySwitch

struct AudioStreamingTests {
    private func makeParser() throws -> Parser {
        let parser = try Parser()
        parser.dataFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: true)!
        return parser
    }

    private func append(_ value: Float, to parser: Parser) {
        var value = value
        withUnsafePointer(to: &value) {
            ParserPacketCallback(Unmanaged.passUnretained(parser).toOpaque(), 4, 1, $0, nil)
        }
    }

    @Test("The converter consumes the only packet and reports zero packets on exhaustion")
    func consumesLastPacket() throws {
        let parser = try makeParser()
        append(0.25, to: parser)
        let reader = try Reader(parser: parser, readFormat: #require(parser.dataFormat))
        let buffer = try reader.read(1)
        #expect(buffer.floatChannelData?[0][0] == 0.25)
        #expect(reader.currentPacket == 1)

        var count: UInt32 = 99
        var list = AudioBufferList()
        let status = ReaderConverterCallback(try #require(reader.converter), &count, &list, nil, Unmanaged.passUnretained(reader).toOpaque())
        #expect(status == ReaderReachedEndOfDataError)
        #expect(count == 0)
    }

    @Test("An empty incomplete stream returns no input without indexing the array")
    func emptyIncompleteStream() throws {
        let parser = try makeParser()
        parser.packetCount = 10
        let reader = try Reader(parser: parser, readFormat: #require(parser.dataFormat))
        var count: UInt32 = 99
        var list = AudioBufferList()
        let status = ReaderConverterCallback(try #require(reader.converter), &count, &list, nil, Unmanaged.passUnretained(reader).toOpaque())
        #expect(status == ReaderNotEnoughDataError)
        #expect(count == 0)
        #expect(reader.currentPacket == 0)
    }

    @Test("Trimming at 256 packets preserves the next packet and final sample")
    func trimsConsumedPackets() throws {
        let parser = try makeParser()
        for value in 0..<600 { append(Float(value), to: parser) }
        let reader = try Reader(parser: parser, readFormat: #require(parser.dataFormat))
        for value in 0..<600 {
            let buffer = try reader.read(1)
            #expect(buffer.floatChannelData?[0][0] == Float(value))
        }
        #expect(parser.withPackets { $0.count } == 88)
        #expect(reader.currentPacket == 88)
    }

    @Test("Input storage stays valid across reads and belongs to each reader")
    func converterInputOwnership() throws {
        let firstParser = try makeParser()
        let secondParser = try makeParser()
        for value in 0..<100 {
            append(Float(value), to: firstParser)
            append(Float(value + 100), to: secondParser)
        }
        let first = try Reader(parser: firstParser, readFormat: #require(firstParser.dataFormat))
        let second = try Reader(parser: secondParser, readFormat: #require(secondParser.dataFormat))
        for value in 0..<100 {
            _ = try first.read(1)
            let firstInput = try #require(first.converterInputData)
            #expect(firstInput.load(as: Float.self) == Float(value))
            _ = try second.read(1)
            #expect(firstInput.load(as: Float.self) == Float(value))
            #expect(first.converterInputData != second.converterInputData)
        }
    }

    @Test("Concurrent packet callbacks and consumption preserve every packet")
    func concurrentProductionAndConsumption() throws {
        let shared = try SharedParser(parser: makeParser())
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            var value = Float(index)
            withUnsafePointer(to: &value) {
                ParserPacketCallback(Unmanaged.passUnretained(shared.parser).toOpaque(), 4, 1, $0, nil)
            }
            let packet = shared.parser.withPackets { packets -> Data? in
                packets.isEmpty ? nil : packets.removeFirst().0
            }
            if let packet { shared.record(packet) }
        }
        let remaining = shared.parser.withPackets { $0.map(\.0) }
        let values = (shared.consumed + remaining).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Float.self) } }
        #expect(values.count == 2_000)
        #expect(Set(values) == Set((0..<2_000).map(Float.init)))
    }

    @Test("Compressed packet descriptions have reader-owned storage and preserve frame counts")
    func compressedInputOwnership() throws {
        let parser = try makeParser()
        let output = try #require(parser.dataFormat)
        let first = try Reader(parser: parser, readFormat: output)
        let second = try Reader(parser: parser, readFormat: output)
        // Exercise the input callback directly, without requesting a system codec
        // or trying to decode the synthetic compressed payload below.
        var format = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatMPEGLayer3,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1_152,
            mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        parser.dataFormat = AVAudioFormat(streamDescription: &format)
        let packetDescription = AudioStreamPacketDescription(mStartOffset: 50, mVariableFramesInPacket: 1_152, mDataByteSize: 4)
        parser.withPackets { $0 = Array(repeating: (Data([1, 2, 3, 4]), packetDescription), count: 100) }
        for _ in 0..<100 {
            var count: UInt32 = 1
            var list = AudioBufferList()
            var description: UnsafeMutablePointer<AudioStreamPacketDescription>?
            let firstStatus = ReaderConverterCallback(try #require(first.converter), &count, &list, &description, Unmanaged.passUnretained(first).toOpaque())
            #expect(firstStatus == noErr)
            let firstDescription = try #require(description)
            #expect(firstDescription == first.converterInputDescription)
            #expect(firstDescription.pointee.mStartOffset == 0)
            #expect(firstDescription.pointee.mVariableFramesInPacket == 1_152)
            #expect(firstDescription.pointee.mDataByteSize == 4)

            let secondStatus = ReaderConverterCallback(try #require(second.converter), &count, &list, &description, Unmanaged.passUnretained(second).toOpaque())
            #expect(secondStatus == noErr)
            #expect(description != firstDescription)
            #expect(firstDescription.pointee.mVariableFramesInPacket == 1_152)
        }
    }

    @Test("Packet append, snapshot, and stop clearing can run concurrently")
    func concurrentBufferClearing() throws {
        let shared = try SharedParser(parser: makeParser())
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            shared.parser.withPackets { $0.append((Data([UInt8(index % 256)]), nil)) }
            _ = shared.parser.packets
            _ = shared.parser.totalPacketCount
            if index.isMultiple(of: 7) {
                shared.parser.withPackets { $0.removeAll() }
            }
        }
        shared.parser.withPackets { $0.removeAll() }
        #expect(shared.parser.withPackets { $0.isEmpty })
    }
}

// Only the Parser's synchronized API crosses threads. Recorded results have a
// separate lock so the stress test never serializes producer and consumer work.
private final class SharedParser: @unchecked Sendable {
    let parser: Parser
    private let lock = NSLock()
    private var recorded: [Data] = []

    init(parser: Parser) { self.parser = parser }

    func record(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(data)
    }

    var consumed: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
