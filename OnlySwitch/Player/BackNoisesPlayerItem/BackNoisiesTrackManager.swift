//
//  BackNoisiesTrackManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation

class BackNoisesTrackManager:ObservableObject {
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
    var currentBackNoisesItem = BackNoisesPlayerItemViewModel()
    
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
    
    init() {
        setPlayItem(track: currentTrack)
    }

    private func setPlayItem(track: Tracks) {
        @Sendable func setTrackURL(trackURL: String) {
            if let item = PlayerManager.shared.player.currentPlayerItem, item.isPlaying {
                if item.type == .BackNoises {
                    PlayerManager.shared.player.stop()
                } else {
                    item.isPlaying = false
                }
            }

            let isPlaying = currentBackNoisesItem.isPlaying
            currentBackNoisesItem.url = URL(string: trackURL)
            currentBackNoisesItem.title = track.rawValue
            currentBackNoisesItem.changeToPreviousTrack = {
                self.changeTrack(action: .previous)
            }

            currentBackNoisesItem.changeToNextTrack = {
                self.changeTrack(action: .next)
            }

            currentBackNoisesItem.isPlaying = isPlaying

            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
        }

        if let trackURL = GitHubPresenter.shared.myAppPath?.appendingPathComponent(string: "backNoises/" + track.fileName()), FileManager.default.fileExists(atPath: trackURL) {
            setTrackURL(trackURL: trackURL)
        } else {
            Task { @MainActor in
                do {
                    let path = try await downloadBackgroundNoises(track: track)
                    setTrackURL(trackURL: path)
                } catch {
                    if let item = PlayerManager.shared.player.currentPlayerItem {
                        item.isPlaying = false
                    }
                }
            }
        }
    }
    
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

    private func downloadBackgroundNoises(track: Tracks) async throws -> String {
        var components = URLComponents()
        components.scheme = httpsScheme
        components.host = URLHost.userContent.rawValue
        components.path = "/" + EndPointKinds.backNoises.rawValue + track.fileName()
        return try await GitHubPresenter.shared.downloadFile(from: components.url!, name: folderName + "/" + track.fileName())
    }
}
