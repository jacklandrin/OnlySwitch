import AVFoundation
import Foundation
import os

/// Only the helper constructs audible AVFoundation players. The host retains UI, Now Playing,
/// track navigation and user preferences, while metadata and waveform samples return over stdout.
@MainActor
final class PlaybackHelperEngine: NSObject, @preconcurrency AVPlayerItemMetadataOutputPushDelegate, StreamingDelegate {
    private var player: AVPlayer?
    private var noise: AVAudioPlayer?
    private var streamer: Streamer?
    private var playbackObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var receivedStreamAudio = false
    private var desiredPlaybackActive = false
    private var playbackID: UUID?
    private let output: FileHandle
    private var volume: Float = 1
    nonisolated private let visible = OSAllocatedUnfairLock(initialState: false)
    private let analyzer = RealtimeAnalyzer(fftSize: bufferSize)

    init(output: FileHandle) { self.output = output; super.init() }

    func announceReady() { emit(.init(isReady: true)) }

    func perform(_ command: PlaybackHelperCommand) {
        switch command.action {
        case .play:
            guard let raw = command.url, raw.utf8.count <= 8_192,
                  let url = URL(string: raw), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return }
            stop()
            playbackID = command.playbackID
            desiredPlaybackActive = true
            setVolume(command.volume ?? volume)
            if command.isNoise == true {
                guard let sound = try? AVAudioPlayer(contentsOf: url) else {
                    emit(.init(isBuffering: false, hasFailed: true)); return
                }
                noise = sound
                sound.numberOfLoops = -1
                sound.volume = volume
                emit(.init(isBuffering: false, hasFailed: !sound.play()))
            } else {
                let item = AVPlayerItem(url: url)
                item.audioTimePitchAlgorithm = .spectral
                item.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
                let metadata = AVPlayerItemMetadataOutput(identifiers: nil)
                metadata.setDelegate(self, queue: .main)
                item.add(metadata)
                let av = AVPlayer(playerItem: item)
                player = av
                itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.player?.currentItem === item else { return }
                        self.emit(.init(isBuffering: false, hasFailed: true))
                    }
                }
                playbackObservation = av.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                    let isBuffering = player.timeControlStatus != .playing
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.player === player, self.desiredPlaybackActive else { return }
                        self.emit(.init(isBuffering: isBuffering))
                    }
                }
                av.volume = volume
                let path = raw.lowercased()
                let useStreamer = command.usesWaveform == true && !path.hasSuffix(".m3u")
                    && !path.hasSuffix(".m3u8") && !path.hasSuffix(".aac")
                av.isMuted = useStreamer
                av.play()
                if useStreamer {
                    let stream = Streamer()
                    stream.delegate = self
                    stream.volume = volume
                    streamer = stream
                    stream.url = url
                    // Preserve incremental live-radio startup before the download ever completes.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak stream] in
                        guard let self, let stream, self.streamer === stream, self.desiredPlaybackActive else { return }
                        stream.play()
                    }
                }
                emit(.init(isBuffering: true))
            }
        case .pause:
            desiredPlaybackActive = false
            player?.pause(); noise?.pause(); streamer?.pause()
            emit(.init(isBuffering: false))
        case .stop:
            stop()
        case .volume:
            setVolume(command.volume ?? volume)
        case .visible:
            visible.withLock { $0 = command.isVisible == true }
        case .shutdown:
            shutdown()
        }
    }

    private func setVolume(_ value: Float) {
        volume = value.isFinite ? min(1, max(0, value)) : 0
        player?.volume = volume
        noise?.volume = volume
        streamer?.setUserVolume(volume)
    }

    private func stop(emitStatus: Bool = true) {
        desiredPlaybackActive = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        noise?.stop()
        streamer?.dispose()
        playbackObservation = nil
        itemObservation = nil
        receivedStreamAudio = false
        player = nil; noise = nil; streamer = nil
        if emitStatus { emit(.init(isBuffering: false)) }
    }

    func shutdown() -> Never { stop(emitStatus: false); exit(EXIT_SUCCESS) }

    private func emit(_ event: PlaybackHelperEvent) {
        var event = event
        event.playbackID = playbackID
        guard var data = try? JSONEncoder().encode(event), data.count <= PlaybackHelperLineFramer.maximumFrameSize else { return }
        data.append(10)
        do { try output.write(contentsOf: data) } catch { shutdown() }
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard player?.currentItem?.outputs.contains(where: { $0 === output }) == true,
              let item = groups.first?.items.first, let title = item.value(forKeyPath: "value") as? String else { return }
        emit(.init(trackInfo: title.trimmingCharacters(in: .newlines), isBuffering: false))
    }

    nonisolated func streamer(_ streamer: Streaming, downloadComplete url: URL) {
        guard let stream = streamer as? Streamer else { return }
        Task { @MainActor [weak self] in
            guard let self, self.streamer === stream, self.desiredPlaybackActive else { return }
            stream.play()
        }
    }

    nonisolated func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL) {
        guard let stream = streamer as? Streamer else { return }
        Task { @MainActor [weak self] in
            guard let self, self.streamer === stream else { return }
            stream.dispose()
            self.streamer = nil
            self.player?.isMuted = false
            if self.desiredPlaybackActive { self.emit(.init(isBuffering: false, isReady: true)) }
        }
    }

    nonisolated func streamer(_ streamer: Streaming, updateBuffer buffer: AVAudioPCMBuffer) {
        guard let stream = streamer as? Streamer else { return }
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        let interleaved = buffer.format.isInterleaved
        let samples: [[Float]]?
        if visible.withLock({ $0 }), buffer.frameLength >= AVAudioFrameCount(bufferSize),
           channelCount > 0, channelCount <= 8, let channels = buffer.floatChannelData {
            // Copy only samples across the actor boundary; the engine owns and reuses its buffer.
            samples = (0..<channelCount).map { channel in
                (0..<bufferSize).map { frame in
                    interleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                }
            }
        } else { samples = nil }
        Task { @MainActor [weak self] in
            guard let self, self.streamer === stream else { return }
            var spectra: [[Float]]?
            if let samples,
               let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount)),
               let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize)),
               let channels = copy.floatChannelData {
                copy.frameLength = AVAudioFrameCount(bufferSize)
                for channel in 0..<channelCount {
                    samples[channel].withUnsafeBufferPointer { source in
                        channels[channel].update(from: source.baseAddress!, count: bufferSize)
                    }
                }
                spectra = self.analyzer.analyse(with: copy)
            }
            let firstAudio = !self.receivedStreamAudio
            self.receivedStreamAudio = true
            if firstAudio || spectra != nil {
                self.emit(.init(spectra: spectra, isBuffering: false, isReady: firstAudio))
            }
        }
    }
    nonisolated func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, forURL url: URL) {}
    nonisolated func streamer(_ streamer: Streaming, changedState state: StreamingState) {}
    nonisolated func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval) {}
    nonisolated func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval) {}
}
