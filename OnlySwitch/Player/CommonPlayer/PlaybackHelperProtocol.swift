import Foundation

/// A bounded, newline-delimited protocol carried only over this app's child-process pipes.
struct PlaybackHelperCommand: Codable, Sendable {
    enum Action: String, Codable, Sendable { case play, pause, stop, volume, visible, shutdown }
    var action: Action
    var url: String?
    var isNoise: Bool?
    var volume: Float?
    var usesWaveform: Bool?
    var isVisible: Bool?
    var playbackID: UUID?
}

struct PlaybackHelperEvent: Codable, Sendable {
    var trackInfo: String?
    var spectra: [[Float]]?
    var isBuffering: Bool?
    var isReady: Bool?
    var hasFailed: Bool?
    var playbackID: UUID?
}

struct PlaybackHelperLineFramer: Sendable {
    enum Failure: Error { case oversizedFrame }
    static let maximumFrameSize = 262_144
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            guard buffer.distance(from: buffer.startIndex, to: newline) <= Self.maximumFrameSize else {
                throw Failure.oversizedFrame
            }
            frames.append(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        guard buffer.count <= Self.maximumFrameSize else { throw Failure.oversizedFrame }
        return frames
    }
}

