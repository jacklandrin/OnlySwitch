import Foundation
import Testing
@testable import AppFeature

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BackNoisesTrackManagerTests {
    @Test(arguments: [BackNoisesTrackManager.Tracks.WhiteNoise, .SoftRain])
    func cachedTrackUsesPlayableFileURLWithoutDownloading(track: BackNoisesTrackManager.Tracks) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlySwitch noise #100% 中文 \(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = root.appendingPathComponent("backNoises", isDirectory: true)
            .appendingPathComponent(track.fileName())
        try FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: expected)

        let manager = BackNoisesTrackManager(
            loadImmediately: false,
            cachePath: { root.path },
            download: { _ in throw UnexpectedDownload() }
        )
        let url = try await manager.resolveTrackURL(track: track)

        #expect(url.isFileURL)
        #expect(url.path == expected.path)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(URL(string: url.absoluteString)?.path == expected.path)
    }

    @Test func downloadedTrackUsesPlayableFileURLAndPreservesFilename() async throws {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlySwitch noise #100% 中文")
            .appendingPathComponent("White Noise.mp3")
        let manager = BackNoisesTrackManager(
            loadImmediately: false,
            cachePath: { nil },
            download: { track in
                #expect(track == .WhiteNoise)
                return expected.path
            }
        )

        let url = try await manager.resolveTrackURL(track: .WhiteNoise)

        #expect(url.isFileURL)
        #expect(url.path == expected.path)
        #expect(URL(string: url.absoluteString)?.path == expected.path)
    }

    @Test func downloadFailureIsNotConvertedIntoAPlayableURL() async {
        let manager = BackNoisesTrackManager(
            loadImmediately: false,
            cachePath: { nil },
            download: { _ in throw UnexpectedDownload() }
        )

        await #expect(throws: UnexpectedDownload.self) {
            try await manager.resolveTrackURL(track: .WhiteNoise)
        }
    }

    private struct UnexpectedDownload: Error {}

    @Test func firstDownloadPreservesPlayIntentUntilURLIsReady() async throws {
        let player = PlaybackSpy()
        let downloads = ControlledDownloads()
        let manager = makeManager(player: player, downloads: downloads)
        manager.currentBackNoisesItem.isPlaying = true
        let task = try #require(manager.setPlayItem(track: .WhiteNoise))
        await downloads.waitForRequest(.WhiteNoise)
        #expect(manager.currentBackNoisesItem.isPlaying)
        #expect(player.playedURLs.isEmpty)

        await downloads.finish(.WhiteNoise, result: .success("/tmp/White Noise.mp3"))
        await task.value

        #expect(player.playedURLs == [URL(fileURLWithPath: "/tmp/White Noise.mp3")])
        #expect(manager.currentBackNoisesItem.isPlaying)
    }

    @Test func turningOffDuringDownloadDoesNotStartPlayback() async throws {
        let player = PlaybackSpy()
        let downloads = ControlledDownloads()
        let manager = makeManager(player: player, downloads: downloads)
        manager.currentBackNoisesItem.isPlaying = true
        let task = try #require(manager.setPlayItem(track: .WhiteNoise))
        await downloads.waitForRequest(.WhiteNoise)
        manager.currentBackNoisesItem.isPlaying = false
        await downloads.finish(.WhiteNoise, result: .success("/tmp/White Noise.mp3"))
        await task.value

        #expect(player.playedURLs.isEmpty)
        #expect(!manager.currentBackNoisesItem.isPlaying)
    }

    @Test func supersededDownloadCannotReplaceSelectedTrack() async throws {
        let player = PlaybackSpy()
        let downloads = ControlledDownloads()
        let manager = makeManager(player: player, downloads: downloads)
        let first = try #require(manager.setPlayItem(track: .WhiteNoise))
        await downloads.waitForRequest(.WhiteNoise)
        let second = try #require(manager.setPlayItem(track: .SoftRain))
        await downloads.waitForRequest(.SoftRain)
        await downloads.finish(.SoftRain, result: .success("/tmp/Soft Rain.mp3"))
        await second.value
        await downloads.finish(.WhiteNoise, result: .success("/tmp/White Noise.mp3"))
        await first.value

        #expect(manager.currentBackNoisesItem.url == URL(fileURLWithPath: "/tmp/Soft Rain.mp3"))
        #expect(manager.currentBackNoisesItem.track == .SoftRain)
    }

    @Test(arguments: [false, true])
    func finishingDownloadPreservesRadioStartedWhileWaiting(fails: Bool) async throws {
        let player = PlaybackSpy()
        let downloads = ControlledDownloads()
        let manager = makeManager(player: player, downloads: downloads)
        manager.currentBackNoisesItem.isPlaying = true
        let task = try #require(manager.setPlayItem(track: .WhiteNoise))
        await downloads.waitForRequest(.WhiteNoise)
        let radio = RadioItem()
        player.currentPlayerItem = radio
        await downloads.finish(.WhiteNoise, result: fails ? .failure(UnexpectedDownload()) : .success("/tmp/White Noise.mp3"))
        await task.value

        #expect(player.currentPlayerItem === radio)
        #expect(radio.isPlaying)
        #expect(player.stopCount == 0)
        #expect(player.playedURLs.isEmpty)
        #expect(!manager.currentBackNoisesItem.isPlaying)
    }

    private func makeManager(player: PlaybackSpy, downloads: ControlledDownloads) -> BackNoisesTrackManager {
        BackNoisesTrackManager(loadImmediately: false, cachePath: { nil }, download: { track in
            try await downloads.request(track)
        }, player: { player })
    }
}

private final class PlaybackSpy: AudioPlayer {
    var currentPlayerItem: CommonPlayerItem?
    var analyzer = RealtimeAnalyzer(fftSize: bufferSize)
    var bufferring = false
    var playedURLs: [URL] = []
    var stopCount = 0

    func play(stream item: CommonPlayerItem) {
        currentPlayerItem = item
        if let url = item.url { playedURLs.append(url) }
    }
    func stop() { stopCount += 1 }
    func pause() {}
}

private final class RadioItem: CommonPlayerItem {
    var isPlaying = true
    var title = "Radio"
    var trackInfo = ""
    var url: URL? = URL(string: "https://example.com/radio")
    var type: PlayerType { .Radio }
    func nextTrack() {}
    func previousTrack() {}
}

private actor ControlledDownloads {
    typealias Track = BackNoisesTrackManager.Tracks
    private var requests: [Track: CheckedContinuation<String, Error>] = [:]
    private var waiters: [Track: CheckedContinuation<Void, Never>] = [:]

    func request(_ track: Track) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            requests[track] = continuation
            waiters.removeValue(forKey: track)?.resume()
        }
    }

    func waitForRequest(_ track: Track) async {
        if requests[track] != nil { return }
        await withCheckedContinuation { waiters[track] = $0 }
    }

    func finish(_ track: Track, result: Result<String, Error>) {
        requests.removeValue(forKey: track)?.resume(with: result)
    }
}
