import AppKit
import AVFoundation
import Foundation
import Darwin
import MediaPlayer
import Switches

/// Legacy AudioPlayer callers are main-thread UI code. Playback itself lives in a child
/// process so the mixer can tap it without capturing the main app's processed replay.
@MainActor
final class HostedAudioPlayer: NSObject, @preconcurrency AudioPlayer {
    nonisolated static let helperArgument = "--onlyswitch-audio-helper"
    weak var currentPlayerItem: CommonPlayerItem?
    var analyzer = RealtimeAnalyzer(fftSize: bufferSize)
    var bufferring = false
    private var process: Process?
    private var commandInput: PlaybackHelperCommandWriter?
    private(set) var helperGeneration: UUID?
    private var isVisible = false
    private var playbackID: UUID?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    var helperProcessIdentifier: pid_t? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func ownsHelperProcess(_ pid: pid_t) -> Bool { helperProcessIdentifier == pid }

    /// MediaPlayer may invoke handlers off the main thread. Only user intent crosses that boundary.
    func configureRemoteCommands() {
        setupNowPlaying()
        MPNowPlayingInfoCenter.default().playbackState = .paused
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.setRemotePlaying(true) }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.setRemotePlaying(false) }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let item = self.currentPlayerItem else { return }
                self.setRemotePlaying(!item.isPlaying)
            }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.changeRemoteTrack(next: true) }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.changeRemoteTrack(next: false) }
            return .success
        }
    }

    private func setRemotePlaying(_ playing: Bool) {
        guard let item = currentPlayerItem else { return }
        item.isPlaying = playing
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus,
                                        object: item.type == .Radio ? SwitchType.radioStation : .backNoises)
    }

    private func changeRemoteTrack(next: Bool) {
        guard let item = currentPlayerItem else { return }
        if next { item.nextTrack() } else { item.previousTrack() }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] = item.title
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] = nil
    }

    func isHelperRunning(pid: pid_t, sessionID: UUID) -> Bool {
        helperGeneration == sessionID && ownsHelperProcess(pid)
    }

    override init() {
        super.init()
        isVisible = NSApplication.shared.isActive
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .volumeChange, object: nil, queue: .main) { [weak self] note in
            guard let volume = note.userInfo?["newValue"] as? Float else { return }
            DispatchQueue.main.async { [weak self] in self?.send(.init(action: .volume, volume: volume)) }
        })
        observers.append(center.addObserver(forName: .showPopover, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.isVisible = true
                self?.send(.init(action: .visible, isVisible: true))
            }
        })
        observers.append(center.addObserver(forName: .hidePopover, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.isVisible = false
                self?.send(.init(action: .visible, isVisible: false))
            }
        })
    }

    func play(stream item: CommonPlayerItem) {
        guard let url = item.url, url.absoluteString.utf8.count <= 8_192,
              ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
            item.isPlaying = false
            return
        }
        if let previous = currentPlayerItem, previous !== item {
            previous.isPlaying = false
            previous.trackInfo = ""
        }
        currentPlayerItem = item
        guard startHelper() else { bufferring = false; item.isPlaying = false; return }
        let playbackID = UUID()
        self.playbackID = playbackID
        bufferring = item.type == .Radio
        send(.init(action: .play, url: url.absoluteString, isNoise: item.type == .BackNoises,
                   volume: Preferences.shared.volume, usesWaveform: Preferences.shared.soundWaveEffectDisplay,
                   playbackID: playbackID))
        send(.init(action: .visible, isVisible: isVisible))
        setupNowPlaying()
        NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
        if let generation = helperGeneration {
            for delay in [0.3, 1.0, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.helperGeneration == generation,
                          self.currentPlayerItem?.isPlaying == true else { return }
                    NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
                }
            }
        }
    }

    func pause() {
        send(.init(action: .pause))
        bufferring = false
        pauseCommandCenter()
        NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
    }

    func stop() {
        send(.init(action: .stop))
        bufferring = false
        pauseCommandCenter()
        NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
    }

    private func startHelper() -> Bool {
        if process?.isRunning == true { return true }
        guard let executable = Bundle.main.executableURL else { return false }
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = [Self.helperArgument]
        child.environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("XCTest") && !key.hasPrefix("XCInject") && key != "DYLD_INSERT_LIBRARIES"
        }
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        let generation = UUID()
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.helperGeneration == generation else { return }
                self.commandInput?.close()
                self.commandInput = nil
                self.process = nil
                self.helperGeneration = nil
                self.bufferring = false
                if let active = PlayerManager.shared.player as? HostedAudioPlayer, active === self {
                    self.currentPlayerItem?.isPlaying = false
                }
                NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
            }
        }
        do { try child.run() } catch { return false }
        process = child
        helperGeneration = generation
        guard let writer = PlaybackHelperCommandWriter(handle: input.fileHandleForWriting, onFailure: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.helperGeneration == generation else { return }
                self.process?.terminate()
            }
        }) else { child.terminate(); return false }
        commandInput = writer
        // The parent must not retain the child ends: closing our input is the helper's EOF signal.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        Self.readLines(output.fileHandleForReading, onLine: { [weak self] data in
            guard let event = try? JSONDecoder().decode(PlaybackHelperEvent.self, from: data) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.helperGeneration == generation else { return }
                guard event.playbackID == nil || event.playbackID == self.playbackID else { return }
                if let info = event.trackInfo {
                    self.currentPlayerItem?.trackInfo = info
                    self.updateStreamInfo(info: info)
                }
                if let spectra = event.spectra {
                    NotificationCenter.default.post(name: .spectra, object: spectra)
                }
                if let buffering = event.isBuffering {
                    let changed = self.bufferring != buffering
                    self.bufferring = buffering
                    if changed { NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil) }
                }
                if event.isReady == true {
                    NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
                }
                if event.hasFailed == true { self.currentPlayerItem?.isPlaying = false }
            }
        }, onEnd: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.helperGeneration == generation, self.process?.isRunning == true else { return }
                self.process?.terminate()
            }
        })
        NotificationCenter.default.post(name: .ownPlaybackStateChanged, object: nil)
        return true
    }

    private func send(_ command: PlaybackHelperCommand) {
        commandInput?.send(command)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        commandInput?.close()
        if process?.isRunning == true { process?.terminate() }
    }

    /// Must run before SwiftUI/AppDelegate initialization in the helper process.
    static func runHelper() -> Never {
        let protocolFD = dup(STDOUT_FILENO)
        guard protocolFD >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { exit(EXIT_FAILURE) }
        let helper = PlaybackHelperEngine(output: FileHandle(fileDescriptor: protocolFD, closeOnDealloc: true))
        helper.announceReady()
        readLines(FileHandle.standardInput, onLine: { data in
            guard let command = try? JSONDecoder().decode(PlaybackHelperCommand.self, from: data) else { return }
            DispatchQueue.main.async { helper.perform(command) }
        }, onEnd: {
            DispatchQueue.main.async { helper.shutdown() }
        })
        RunLoop.main.run()
        exit(EXIT_SUCCESS)
    }

    nonisolated private static func readLines(_ handle: FileHandle,
                                              onLine: @escaping @Sendable (Data) -> Void,
                                              onEnd: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var framer = PlaybackHelperLineFramer()
            var storage = [UInt8](repeating: 0, count: 16_384)
            defer { try? handle.close(); onEnd() }
            do {
                while true {
                    let count = Darwin.read(handle.fileDescriptor, &storage, storage.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { return }
                    let bytes = Data(storage.prefix(count))
                    for line in try framer.append(bytes) { onLine(line) }
                }
            } catch { return }
        }
    }
}

