import AudioToolbox
import CSoundMixerEQ
import Foundation
import Testing
@testable import SoundMixerEQ

struct OutputRoutingAudioBuffersTests {
    @Test func routesEachFrameToTwoStereoDestinationsAndClearsTails() throws {
        let state = try routed([(0, 2), (2, 2)], totalChannels: 4)
        defer { OSEQDestroy(state) }
        let input = RoutingBufferFixture(channels: [2], frames: 3)
        input.write([0.1, -0.1, 0.2, -0.2, 0.3, -0.3], to: 0)
        let output = RoutingBufferFixture(channels: [2, 2], frames: 5, fill: 99)
        OSEQProcessAudioBuffers(state, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
        #expect(output.values(0) == [0.1, -0.1, 0.2, -0.2, 0.3, -0.3, 0, 0, 0, 0])
        #expect(output.values(1) == output.values(0))
    }

    @Test func mixedStereoMonoAndWideDestinationsDownmixAndClearUnusedChannels() throws {
        let state = try routed([(0, 2), (2, 1), (3, 4)], totalChannels: 7)
        defer { OSEQDestroy(state) }
        let input = RoutingBufferFixture(channels: [2], frames: 2)
        input.write([0.2, 0.4, -0.2, 0.1], to: 0)
        let output = RoutingBufferFixture(channels: [2, 1, 4], frames: 3, fill: 99)
        OSEQProcessAudioBuffers(state, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
        #expect(output.values(0) == [0.2, 0.4, -0.2, 0.1, 0, 0])
        let mono = output.values(1)
        #expect(abs(mono[0] - 0.3) < 0.000001)
        #expect(abs(mono[1] + 0.05) < 0.000001)
        #expect(mono[2] == 0)
        #expect(output.values(2) == [0.2, 0.4, 0, 0, -0.2, 0.1, 0, 0, 0, 0, 0, 0])
    }

    @Test func planarAndInterleavedFanoutAdvancesEQAndGainOnlyOnce() throws {
        let reference = try #require(OSEQCreate(48_000, 2))
        let fanout = try routed([(0, 2), (2, 2)], totalChannels: 4)
        defer { OSEQDestroy(reference); OSEQDestroy(fanout) }
        var settings = EqualizerSettings.flat
        settings.setGain(-8, band: 5)
        EqualizerDSP.publish(settings, sampleRate: 48_000, to: reference)
        EqualizerDSP.publish(settings, sampleRate: 48_000, to: fanout)
        OSEQSetGain(reference, 0.6)
        OSEQSetGain(fanout, 0.6)
        let input = RoutingBufferFixture(channels: [2], frames: 256)
        let single = RoutingBufferFixture(channels: [2], frames: 256)
        // First output is planar, second interleaved: global channels 0...3.
        let multiple = RoutingBufferFixture(channels: [1, 1, 2], frames: 256, fill: 99)
        for block in 0..<8 {
            let values: [Float] = (0..<256).flatMap { frame in
                let sample = Float(0.1 * sin(Double(block * 256 + frame) * 0.13))
                return [sample, sample * -0.5]
            }
            input.write(values, to: 0)
            OSEQProcessAudioBuffers(reference, input.list.unsafeMutablePointer, single.list.unsafeMutablePointer)
            OSEQProcessAudioBuffers(fanout, input.list.unsafeMutablePointer, multiple.list.unsafeMutablePointer)
            let expected = single.values(0)
            let left = multiple.values(0), right = multiple.values(1), stereo = multiple.values(2)
            #expect(stereo == expected)
            let leftMatches = (0..<256).allSatisfy { left[$0] == expected[$0 * 2] }
            let rightMatches = (0..<256).allSatisfy { right[$0] == expected[$0 * 2 + 1] }
            #expect(leftMatches)
            #expect(rightMatches)
        }
    }

    @Test func rejectsOverlappingOutOfRangeEmptyAndOversizedMaps() {
        let invalid: [([(UInt32, UInt32)], UInt32)] = [
            ([], 4), ([(0, 0)], 4), ([(3, 2)], 4), ([(0, 2), (1, 2)], 4),
            ([(UInt32.max, 2)], 4), ([(0, 2)], 0), ([(0, 2)], 1025),
            ((0..<17).map { (UInt32($0), 1) }, 17)
        ]
        for (ranges, total) in invalid {
            let entries = ranges.map { OSEQOutputRange(firstChannel: $0.0, channelCount: $0.1) }
            let state = entries.withUnsafeBufferPointer { OSEQCreateRouted(48_000, 2, $0.baseAddress, UInt32($0.count), total) }
            #expect(state == nil)
            if let state { OSEQDestroy(state) }
        }
    }

    @Test func mapMismatchRetiredStateAndMissingInputClearAllDestinations() throws {
        let state = try routed([(0, 2), (2, 2)], totalChannels: 4)
        defer { OSEQDestroy(state) }
        let input = RoutingBufferFixture(channels: [2], frames: 2)
        input.write([0.1, 0.2, 0.3, 0.4], to: 0)
        let shortLayout = RoutingBufferFixture(channels: [2], frames: 2, fill: 99)
        OSEQProcessAudioBuffers(state, input.list.unsafeMutablePointer, shortLayout.list.unsafeMutablePointer)
        #expect(shortLayout.values(0) == [0, 0, 0, 0])
        let output = RoutingBufferFixture(channels: [2, 2], frames: 2, fill: 99)
        OSEQProcessAudioBuffers(state, nil, output.list.unsafeMutablePointer)
        #expect(output.values(0) == [0, 0, 0, 0])
        #expect(output.values(1) == [0, 0, 0, 0])
        output.write([99, 99, 99, 99], to: 0)
        output.write([99, 99, 99, 99], to: 1)
        OSEQRetire(state)
        OSEQProcessAudioBuffers(state, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
        #expect(output.values(0) == [0, 0, 0, 0])
        #expect(output.values(1) == [0, 0, 0, 0])
    }

    private func routed(_ ranges: [(UInt32, UInt32)], totalChannels: UInt32) throws -> OpaquePointer {
        let entries = ranges.map { OSEQOutputRange(firstChannel: $0.0, channelCount: $0.1) }
        return try entries.withUnsafeBufferPointer {
            try #require(OSEQCreateRouted(48_000, 2, $0.baseAddress, UInt32($0.count), totalChannels))
        }
    }
}

private final class RoutingBufferFixture {
    let list: UnsafeMutableAudioBufferListPointer
    private let storage: [UnsafeMutablePointer<Float>]
    private let counts: [Int]
    init(channels: [Int], frames: Int, fill: Float = 0) {
        list = AudioBufferList.allocate(maximumBuffers: channels.count)
        counts = channels.map { $0 * frames }
        storage = counts.map {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: $0)
            pointer.initialize(repeating: fill, count: $0)
            return pointer
        }
        for index in channels.indices {
            list[index] = AudioBuffer(mNumberChannels: UInt32(channels[index]), mDataByteSize: UInt32(counts[index] * MemoryLayout<Float>.size), mData: storage[index])
        }
    }
    func write(_ values: [Float], to index: Int) {
        for (offset, value) in values.enumerated() { storage[index][offset] = value }
    }
    func values(_ index: Int) -> [Float] { Array(UnsafeBufferPointer(start: storage[index], count: counts[index])) }
    deinit {
        for index in storage.indices { storage[index].deinitialize(count: counts[index]); storage[index].deallocate() }
        list.unsafeMutablePointer.deallocate()
    }
}
