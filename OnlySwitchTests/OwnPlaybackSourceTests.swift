import Testing
import Foundation
@testable import OnlySwitch

@MainActor
struct OwnPlaybackSourceTests {
    @Test func noRowWhileNothingPlays() {
        #expect(SoundMixerVM.ownPlaybackRow(isPlaying: false, volume: 80, previous: nil, icon: nil) == nil)
    }

    @Test func playingRowKeepsNativeVolumeAndOmitsRawAudioHandles() throws {
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 40, previous: nil, icon: nil))
        #expect(row.id == OwnPlaybackSource.rowID)
        #expect(row.name == "OnlySwitch")
        #expect(row.control == .ownPlayer)
        #expect(row.volume == 40)
        #expect(row.isMuted == false)
        #expect(row.volumeBeforeMute == 40)
        #expect(row.pid == nil)
        #expect(row.processObjectIDs.isEmpty)
    }

    @Test func zeroVolumeIsMutedAndKeepsRestoreLevel() throws {
        let previous = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 70, previous: nil, icon: nil))
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 0, previous: previous, icon: nil))
        #expect(row.isMuted)
        #expect(row.volumeBeforeMute == 70)
    }

    @Test func volumeIsClamped() throws {
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 140, previous: nil, icon: nil))
        #expect(row.volume == 100)
    }

    @Test func helperFramingPreservesFragmentedCommandsAndSeparatesMultipleFrames() throws {
        var framer = PlaybackHelperLineFramer()
        #expect(try framer.append(Data("{\"action\":\"pau".utf8)).isEmpty)
        let frames = try framer.append(Data("se\"}\n{\"action\":\"stop\"}\npartial".utf8))
        #expect(frames.map { String(decoding: $0, as: UTF8.self) } == ["{\"action\":\"pause\"}", "{\"action\":\"stop\"}"])
        #expect(try framer.append(Data()).isEmpty)
        #expect(try framer.append(Data(" tail\n".utf8)) == [Data("partial tail".utf8)])
    }

    @Test func helperFramingAcceptsMaximumSizeFrame() throws {
        var framer = PlaybackHelperLineFramer()
        let payload = Data(repeating: 120, count: PlaybackHelperLineFramer.maximumFrameSize)
        #expect(try framer.append(payload).isEmpty)
        #expect(try framer.append(Data([10])) == [payload])
    }

    @Test(arguments: [false, true])
    func helperFramingRejectsOversizedCompleteAndPartialFrames(hasNewline: Bool) {
        var framer = PlaybackHelperLineFramer()
        var payload = Data(repeating: 120, count: PlaybackHelperLineFramer.maximumFrameSize + 1)
        if hasNewline { payload.append(10) }
        #expect(throws: PlaybackHelperLineFramer.Failure.self) {
            try framer.append(payload)
        }
    }

    @Test func helperPlayCommandPreservesPlaybackConfiguration() throws {
        let command = PlaybackHelperCommand(action: .play, url: "https://example.com/live.m3u8",
                                            isNoise: false, volume: 0.35, usesWaveform: true, isVisible: true)
        let decoded = try JSONDecoder().decode(PlaybackHelperCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded.action == .play)
        #expect(decoded.url == command.url)
        #expect(decoded.isNoise == false)
        #expect(decoded.volume == 0.35)
        #expect(decoded.usesWaveform == true)
        #expect(decoded.isVisible == true)
    }

    @Test(arguments: [PlaybackHelperCommand.Action.pause, .stop, .volume, .visible, .shutdown])
    func helperControlCommandsDecodeWithoutPlaybackURL(action: PlaybackHelperCommand.Action) throws {
        let command = PlaybackHelperCommand(action: action)
        let decoded = try JSONDecoder().decode(PlaybackHelperCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded.action == action)
        #expect(decoded.url == nil)
    }

    @Test func helperProtocolRejectsUnknownCommandsAndPreservesEvents() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlaybackHelperCommand.self, from: Data("{\"action\":\"execute\"}".utf8))
        }
        let event = PlaybackHelperEvent(trackInfo: "Station — Artist", spectra: [[0.25, 0.5]], isBuffering: false, isReady: true)
        let decoded = try JSONDecoder().decode(PlaybackHelperEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded.trackInfo == event.trackInfo)
        #expect(decoded.spectra == event.spectra)
        #expect(decoded.isBuffering == false)
        #expect(decoded.isReady == true)
    }

    @Test func helperProcessesShortCommandsBeforeItsInputPipeCloses() async throws {
        let executable = try #require(Bundle.main.executableURL)
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [HostedAudioPlayer.helperArgument]
        process.environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("XCTest") && !key.hasPrefix("XCInject") && !key.hasPrefix("DYLD_")
                && !key.hasPrefix("XCODE") && !key.hasPrefix("__XCODE")
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        defer {
            if process.isRunning { process.terminate() }
            try? input.fileHandleForReading.close()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }

        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        // Keep stdin open: a short pipe frame must dispatch without waiting for EOF or 16 KiB.
        try input.fileHandleForWriting.write(contentsOf: Data("{\"action\":\"stop\"}\n{\"action\":\"shutdown\"}\n".utf8))
        let deadline = ContinuousClock.now + .seconds(3)
        while process.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(process.isRunning == false, "The helper must process short commands while stdin remains open")
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 0)

        let bytes = try output.fileHandleForReading.readToEnd() ?? Data()
        var framer = PlaybackHelperLineFramer()
        let events = try framer.append(bytes).map { try JSONDecoder().decode(PlaybackHelperEvent.self, from: $0) }
        #expect(events.contains { $0.isReady == true })
        #expect(events.contains { $0.isBuffering == false })
    }

}
