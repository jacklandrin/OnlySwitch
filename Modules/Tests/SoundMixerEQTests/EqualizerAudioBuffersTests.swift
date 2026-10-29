import AudioToolbox
import CSoundMixerEQ
import Testing

struct EqualizerAudioBuffersTests {
    @Test func callbackConvertsStereoLayoutAndClearsTrailingFrames() throws {
        let state = try #require(OSEQCreate(48_000, 2))
        defer { OSEQDestroy(state) }
        var samples: [Float] = [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]
        var left = [Float](repeating: 99, count: 5)
        var right = [Float](repeating: 99, count: 5)
        let input = AudioBufferList.allocate(maximumBuffers: 1)
        let output = AudioBufferList.allocate(maximumBuffers: 2)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        samples.withUnsafeMutableBufferPointer { source in
            left.withUnsafeMutableBufferPointer { lhs in
                right.withUnsafeMutableBufferPointer { rhs in
                    input[0] = buffer(source, channels: 2)
                    output[0] = buffer(lhs, channels: 1)
                    output[1] = buffer(rhs, channels: 1)
                    OSEQProcessAudioBuffers(state, input.unsafeMutablePointer, output.unsafeMutablePointer)
                }
            }
        }
        #expect(left == [0.1, 0.2, 0.3, 0, 0])
        #expect(right == [-0.1, -0.2, -0.3, 0, 0])
        #expect(OSEQSawAudio(state))
    }

    @Test func callbackGainRampStaysAlignedAcrossChannels() throws {
        let state = try #require(OSEQCreate(48_000, 2))
        defer { OSEQDestroy(state) }
        OSEQSetGain(state, 0.5)
        var left = [Float](repeating: 0.2, count: 256)
        var right = [Float](repeating: 0.2, count: 256)
        var rendered = [Float](repeating: 99, count: 512)
        let input = AudioBufferList.allocate(maximumBuffers: 2)
        let output = AudioBufferList.allocate(maximumBuffers: 1)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        left.withUnsafeMutableBufferPointer { lhs in
            right.withUnsafeMutableBufferPointer { rhs in
                rendered.withUnsafeMutableBufferPointer { destination in
                    input[0] = buffer(lhs, channels: 1)
                    input[1] = buffer(rhs, channels: 1)
                    output[0] = buffer(destination, channels: 2)
                    OSEQProcessAudioBuffers(state, input.unsafeMutablePointer, output.unsafeMutablePointer)
                }
            }
        }
        #expect(stride(from: 0, to: rendered.count, by: 2).allSatisfy { rendered[$0] == rendered[$0 + 1] })
        #expect(abs(rendered[510] - 0.1) < 0.000001)
        #expect(rendered[0] > rendered[510])
    }

    @Test func retiredOrMalformedCallbackAlwaysSilencesOutput() throws {
        let state = try #require(OSEQCreate(48_000, 2))
        defer { OSEQDestroy(state) }
        var samples: [Float] = [0.2, 0.2]
        var rendered = [Float](repeating: 99, count: 4)
        let input = AudioBufferList.allocate(maximumBuffers: 1)
        let output = AudioBufferList.allocate(maximumBuffers: 1)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        samples.withUnsafeMutableBufferPointer { source in
            rendered.withUnsafeMutableBufferPointer { destination in
                input[0] = buffer(source, channels: 0)
                output[0] = buffer(destination, channels: 2)
                OSEQProcessAudioBuffers(state, input.unsafeMutablePointer, output.unsafeMutablePointer)
            }
        }
        #expect(rendered == [0, 0, 0, 0])
        OSEQRetire(state)
        rendered = [99, 99, 99, 99]
        samples.withUnsafeMutableBufferPointer { source in
            rendered.withUnsafeMutableBufferPointer { destination in
                input[0] = buffer(source, channels: 2)
                output[0] = buffer(destination, channels: 2)
                OSEQProcessAudioBuffers(state, input.unsafeMutablePointer, output.unsafeMutablePointer)
            }
        }
        #expect(rendered == [0, 0, 0, 0])
    }

    private func buffer(_ samples: UnsafeMutableBufferPointer<Float>, channels: UInt32) -> AudioBuffer {
        AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size), mData: samples.baseAddress)
    }
}
