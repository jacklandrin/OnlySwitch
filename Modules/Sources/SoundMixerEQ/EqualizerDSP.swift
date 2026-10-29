import CSoundMixerEQ
import Foundation

/// One control-thread writer and one audio-thread reader. Only the C state crosses that boundary.
/// The test wrapper owns its allocation; Core Audio uses the raw allocation for its longer lifetime.
public final class EqualizerDSP {
    private let state: OpaquePointer
    private let sampleRate: Double
    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        guard let state = OSEQCreate(sampleRate, UInt32(channels)) else { preconditionFailure("Unsupported EQ format") }
        self.state = state
    }
    deinit { OSEQDestroy(state) }
    public func update(_ settings: EqualizerSettings) {
        Self.publish(settings, sampleRate: sampleRate, to: state)
    }
    public func process(_ samples: UnsafeMutableBufferPointer<Float>, channels: Int) {
        guard channels > 0 else { return }
        OSEQProcessInterleaved(state, samples.baseAddress, samples.count / channels, UInt32(channels))
    }
    public func processPlanar(left: UnsafeMutableBufferPointer<Float>, right: UnsafeMutableBufferPointer<Float>) {
        OSEQProcessPlanar(state, left.baseAddress, right.baseAddress, min(left.count, right.count))
    }
    /// Coefficient computation only runs on the control side, never inside the render callback.
    public static func publish(_ settings: EqualizerSettings, sampleRate: Double, to state: OpaquePointer) {
        var coefficients = [Double]()
        coefficients.reserveCapacity(50)
        for (frequency, gain) in zip(EqualizerSettings.frequencies, settings.gains) {
            guard gain != 0, sampleRate.isFinite, sampleRate > 0, frequency < sampleRate * 0.45 else {
                coefficients.append(contentsOf: [1, 0, 0, 0, 0]); continue
            }
            let a = pow(10, gain / 40)
            let angle = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(angle) / (2 * 1.4)
            let a0 = 1 + alpha / a
            coefficients.append(contentsOf: [(1 + alpha * a) / a0, -2 * cos(angle) / a0,
                                             (1 - alpha * a) / a0, -2 * cos(angle) / a0, (1 - alpha / a) / a0])
        }
        coefficients.withUnsafeBufferPointer { OSEQPublish(state, $0.baseAddress) }
    }
}
