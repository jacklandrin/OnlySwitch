//
//  BackNoisiesTrackManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation
import Networking
import Switches

final class BackNoisesTrackManager:ObservableObject, @unchecked Sendable {
    enum Tracks:String {
        case WhiteNoise = "White Noise"
        case PinkNoise = "Pink Noise"
        case Brownian = "Brownian"
        case MeadowBirds = "Meadow Birds"
        case ForestWalking = "Forest Walking"
        case SoftRain = "Soft Rain"
        case MotorBoat = "Motor Boat"
        case HarborWave = "Harbor Wave"
        case CrowdUrban = "Crowd Urban"
        case Meditation = "Meditation"
        case Fireplace = "Fireplace"

        func fileName() -> String {
            rawValue + ".mp3"
        }
    }
    
    static let shared = BackNoisesTrackManager()
    let currentBackNoisesItem: BackNoisesPlayerItemViewModel
    
    var currentTrack:Tracks {
        get {
            Tracks(rawValue: Preferences.shared.backNoisesTrack) ?? .WhiteNoise
        }
        set {
            Preferences.shared.backNoisesTrack = newValue.rawValue
            setPlayItem(track: newValue)
            objectWillChange.send()
        }
    }
    
    private var currentTrackIndex:Int {
        trackList.indices.filter { trackList[$0] == currentTrack }.first ?? 0
    }

    private let folderName = "backNoises"
    private let cachePath: @Sendable () -> String?
    private let download: @Sendable (Tracks) async throws -> String
    private let player: () -> AudioPlayer
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()

    let trackList:[Tracks] = [
        .WhiteNoise,
        .PinkNoise,
        .Brownian,
        .MeadowBirds,
        .ForestWalking,
        .SoftRain,
        .MotorBoat,
        .HarborWave,
        .CrowdUrban,
        .Meditation,
        .Fireplace
    ]
    
    init(
        loadImmediately: Bool = true,
        cachePath: @escaping @Sendable () -> String? = { GitHubPresenter.shared.myAppPath },
        download: @escaping @Sendable (Tracks) async throws -> String = { track in
            try await BackNoisesTrackManager.downloadBackgroundNoises(track: track)
        },
        player: @escaping () -> AudioPlayer = { PlayerManager.shared.player }
    ) {
        self.cachePath = cachePath
        self.download = download
        self.player = player
        self.currentBackNoisesItem = BackNoisesPlayerItemViewModel(player: player)
        if loadImmediately { setPlayItem(track: currentTrack) }
    }

    @discardableResult
    func setPlayItem(track: Tracks) -> Task<Void, Never>? {
        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        currentBackNoisesItem.title = track.rawValue
        currentBackNoisesItem.changeToPreviousTrack = { [weak self] in self?.changeTrack(action: .previous) }
        currentBackNoisesItem.changeToNextTrack = { [weak self] in self?.changeTrack(action: .next) }

        // Claim playback now, so a radio started during the download can supersede it.
        if currentBackNoisesItem.isPlaying,
           let item = player().currentPlayerItem,
           item !== currentBackNoisesItem, item.isPlaying {
            item.isPlaying = false
        }

        if let trackURL = cachedTrackURL(track: track) {
            applyTrackURL(trackURL)
            return nil
        } else {
            currentBackNoisesItem.url = nil
            loadTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let url = try await resolveTrackURL(track: track)
                    guard !Task.isCancelled, loadGeneration == generation else { return }
                    applyTrackURL(url)
                } catch {
                    guard !Task.isCancelled, loadGeneration == generation else { return }
                    currentBackNoisesItem.isPlaying = false
                    NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
                }
            }
            return loadTask
        }
    }

    private func applyTrackURL(_ trackURL: URL) {
        // A different source started while we were downloading: preserve that newer intent.
        if currentBackNoisesItem.isPlaying,
           let item = player().currentPlayerItem,
           item !== currentBackNoisesItem, item.isPlaying {
            currentBackNoisesItem.isPlaying = false
        }
        let isPlaying = currentBackNoisesItem.isPlaying
        currentBackNoisesItem.url = trackURL
        currentBackNoisesItem.isPlaying = isPlaying
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
    }

    private func cachedTrackURL(track: Tracks) -> URL? {
        guard let path = cachePath() else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(track.fileName())
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return url
    }

    func resolveTrackURL(track: Tracks) async throws -> URL {
        if let url = cachedTrackURL(track: track) { return url }
        return URL(fileURLWithPath: try await download(track))
    }

    deinit { loadTask?.cancel() }
    
    func changeTrack(action:ChangeTrackAction) {
        let newIndex:Int!
        switch action {
        case .next:
            newIndex = self.currentTrackIndex < self.trackList.count - 1 ? self.currentTrackIndex + 1 : 0
        case .previous:
            newIndex = self.currentTrackIndex > 0 ? self.currentTrackIndex - 1 : self.trackList.count - 1
        }
        self.currentTrack = self.trackList[newIndex]
        
    }

    func clearCache() throws {
        guard let myAppPath = GitHubPresenter.shared.myAppPath else {
            return
        }

        let backNoisesFolder = myAppPath.appendingPathComponent(string: folderName)
        let fileUrls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: backNoisesFolder), includingPropertiesForKeys: nil, options: .includesDirectoriesPostOrder)
        for fileUrl in fileUrls {
            try FileManager.default.removeItem(at: fileUrl)
        }
    }

    func cacheSize() -> Int {
        guard let myAppPath = GitHubPresenter.shared.myAppPath else {
            return 0
        }

        let backNoisesFolder = myAppPath.appendingPathComponent(string: folderName)
        let backNoisesFolderUrl = URL(fileURLWithPath: backNoisesFolder)
        var size = 0
        do {
            size = try backNoisesFolderUrl.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
        } catch {
            size = 0
        }
        return size
    }

    private static func downloadBackgroundNoises(track: Tracks) async throws -> String {
        var components = URLComponents()
        components.scheme = httpsScheme
        components.host = URLHost.userContent.rawValue
        components.path = "/" + EndPointKinds.backNoises.rawValue + track.fileName()
        return try await GitHubPresenter.shared.downloadFile(from: components.url!, name: "backNoises/" + track.fileName())
    }
}
