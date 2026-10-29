import Foundation
import Testing
@testable import SoundMixerEQ

struct EqualizerDSPTests {
    @Test func flatPreservesSamples() {
        let dsp = EqualizerDSP(sampleRate: 48_000, channels: 2)
        var samples: [Float] = [0.1, 0, -0.2, 0.05, 0.3, -0.1]
        let original = samples
        samples.withUnsafeMutableBufferPointer { dsp.process($0, channels: 2) }
        #expect(zip(samples, original).allSatisfy { abs($0 - $1) < 0.00001 })
    }

    @Test(arguments: [44_100.0, 48_000.0, 96_000.0])
    func cutsTargetBandAndPreservesDistantBand(sampleRate: Double) {
        var settings = EqualizerSettings.flat
        settings.setGain(-12, band: 5)
        #expect(measuredGain(settings, frequency: 1_000, sampleRate: sampleRate) < 0.4)
        #expect(measuredGain(settings, frequency: 8_000, sampleRate: sampleRate) > 0.8)
    }

    @Test func boostsTargetBand() {
        var settings = EqualizerSettings.flat
        settings.setGain(6, band: 5)
        let gain = measuredGain(settings, frequency: 1_000, sampleRate: 48_000)
        #expect(gain > 1.7)
        #expect(gain < 2.3)
    }

    @Test func channelsDoNotShareHistory() {
        let dsp = EqualizerDSP(sampleRate: 48_000, channels: 2)
        var settings = EqualizerSettings.flat
        settings.setGain(-12, band: 5)
        dsp.update(settings)
        var samples = [Float](repeating: 0, count: 4096)
        samples[0] = 0.1
        samples.withUnsafeMutableBufferPointer { dsp.process($0, channels: 2) }
        #expect(stride(from: 1, to: samples.count, by: 2).allSatisfy { samples[$0] == 0 })
        #expect(samples.allSatisfy { $0.isFinite })
    }

    @Test func planarAndInterleavedOutputAgree() {
        let interleavedDSP = EqualizerDSP(sampleRate: 48_000, channels: 2)
        let planarDSP = EqualizerDSP(sampleRate: 48_000, channels: 2)
        var settings = EqualizerSettings.flat
        settings.setGain(-8, band: 2)
        settings.setGain(4, band: 7)
        interleavedDSP.update(settings)
        planarDSP.update(settings)
        var left = tone(frequency: 125, sampleRate: 48_000, frames: 8192)
        var right = tone(frequency: 4_000, sampleRate: 48_000, frames: 8192)
        var interleaved = zip(left, right).flatMap { [$0, $1] }
        processBlocks(&interleaved, dsp: interleavedDSP, channels: 2)
        for start in stride(from: 0, to: left.count, by: 256) {
            let count = min(256, left.count - start)
            left.withUnsafeMutableBufferPointer { lhs in
                right.withUnsafeMutableBufferPointer { rhs in
                    planarDSP.processPlanar(
                        left: UnsafeMutableBufferPointer(rebasing: lhs[start..<(start + count)]),
                        right: UnsafeMutableBufferPointer(rebasing: rhs[start..<(start + count)]))
                }
            }
        }
        #expect(left.indices.allSatisfy { abs(left[$0] - interleaved[$0 * 2]) < 0.0001 })
        #expect(right.indices.allSatisfy { abs(right[$0] - interleaved[$0 * 2 + 1]) < 0.0001 })
    }

    @Test func resetReturnsToFlatResponse() {
        let dsp = EqualizerDSP(sampleRate: 48_000, channels: 1)
        var settings = EqualizerSettings.flat
        settings.setGain(-12, band: 5)
        dsp.update(settings)
        var warmup = tone(frequency: 1_000, sampleRate: 48_000, frames: 24_000)
        processBlocks(&warmup, dsp: dsp, channels: 1)
        dsp.update(.flat)
        var samples = tone(frequency: 1_000, sampleRate: 48_000, frames: 24_000)
        let original = samples
        processBlocks(&samples, dsp: dsp, channels: 1)
        #expect(zip(samples.dropFirst(4_800), original.dropFirst(4_800)).allSatisfy { abs($0 - $1) < 0.0001 })
    }

    @Test func malformedAndExtremeInputsStayFinite() {
        let dsp = EqualizerDSP(sampleRate: 48_000, channels: 1)
        dsp.update(EqualizerSettings(gains: [99, -99, .nan, .infinity, 12, 12, 12, 12, 12, 12]))
        var samples: [Float] = [.nan, .infinity, -.infinity, 0, 0.01, -0.01]
        processBlocks(&samples, dsp: dsp, channels: 1)
        #expect(samples.allSatisfy { $0.isFinite })
        var silence = [Float](repeating: 0, count: 4096)
        processBlocks(&silence, dsp: dsp, channels: 1)
        #expect(silence.allSatisfy { $0.isFinite })
    }

    private func measuredGain(_ settings: EqualizerSettings, frequency: Double, sampleRate: Double) -> Double {
        let dsp = EqualizerDSP(sampleRate: sampleRate, channels: 1)
        dsp.update(settings)
        var samples = tone(frequency: frequency, sampleRate: sampleRate, frames: Int(sampleRate))
        let original = samples
        processBlocks(&samples, dsp: dsp, channels: 1)
        return rms(samples.dropFirst(Int(sampleRate / 10))) / rms(original.dropFirst(Int(sampleRate / 10)))
    }

    private func tone(frequency: Double, sampleRate: Double, frames: Int) -> [Float] {
        (0..<frames).map { Float(0.05 * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    private func processBlocks(_ samples: inout [Float], dsp: EqualizerDSP, channels: Int) {
        let block = 256 * channels
        samples.withUnsafeMutableBufferPointer { buffer in
            for start in stride(from: 0, to: buffer.count, by: block) {
                dsp.process(UnsafeMutableBufferPointer(rebasing: buffer[start..<min(start + block, buffer.count)]), channels: channels)
            }
        }
    }
}
