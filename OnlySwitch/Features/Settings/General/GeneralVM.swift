//
//  GeneralVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/5.
//

import AppKit
import Combine
import KeyboardShortcuts
import Networking
import Sharing
import Foundation

@MainActor
class GeneralVM: ObservableObject {
    
    @Published private var model = GeneralModel()
    @Published var preferences = Preferences.shared
    @Published var invokePopoverName: KeyboardShortcuts.Name = .invokePopoverShortcutsName
    @Published var currentAppearance: String {
        didSet {
            preferences.currentAppearance = currentAppearance
        }
    }

    @Shared(.appStorage(UserDefaults.Key.hideMenuAfterRunning)) var hideMenuAfterRunningShared: Bool = false
    
    var cacheSize:String {
        get {
            return model.cacheSize
        }
        set {
            model.cacheSize = newValue
        }
    }
    
    var needtoUpdateAlert:Bool {
        get {
            return model.needtoUpdateAlert
        }
        set {
            model.needtoUpdateAlert = newValue
        }
    }
    
    var showProgress: Bool {
        return model.showProgress
    }
    
    var newestVersion: String {
        return model.newestVersion
    }
    
    var supportedLanguages: [Language] {
        return model.supportedLanguages
    }
    
    var showMenubarIconPopover: Bool {
        get {
            return model.showMenubarIconPopover
        }
        set {
            model.showMenubarIconPopover = newValue
        }
    }
    
    var menubarIcons: [String] {
        return model.menubarIcons
    }
    
    private let checkUpdatePresenter = GitHubPresenter.shared
    
    var currentMenubarIcon:String
    {
        get {
            preferences.currentMenubarIcon
        }
        set {
            preferences.currentMenubarIcon = newValue
        }
    }
    
    var showAds: Bool {
        get {
            preferences.showAds
        }
        set {
            preferences.showAds = newValue
        }
    }
    
    var latestVersion: String {
        return checkUpdatePresenter.latestVersion
    }
    
    var isTheNewestVersion: Bool {
        return checkUpdatePresenter.isTheNewestVersion
    }
    
    var showErrorToast: Bool {
        get {
            model.showErrorToast
        }
        set {
            model.showErrorToast = newValue
        }
    }
    
    var errorInfo: String {
        model.errorInfo
    }
    
    var checkIfUpdateOnlaunch: Bool {
        get {
            preferences.checkUpdateOnLaunch
        }

        set {
            preferences.checkUpdateOnLaunch = newValue
        }
    }

    var hideMenuAfterRunning: Bool {
        get {
            hideMenuAfterRunningShared
        }
        
        set {
            $hideMenuAfterRunningShared.withLock { $0 = newValue }
        }
    }
    
    private var cancellable = Set<AnyCancellable>()
    
    init() {
        currentAppearance = Preferences.shared.currentAppearance
        checkUpdatePresenter.objectWillChange.sink{ _ in
            self.objectWillChange.send()
        }.store(in: &cancellable)
    }
    
    func clearCache() {
        do {
            try WallpaperManager.shared.clearCache()
            try BackNoisesTrackManager.shared.clearCache()
        } catch {
            if let error = error as? WallpaperManager.WallpaperError,
               error == WallpaperManager.WallpaperError.ExistsIgnoredFile {
                model.errorInfo = "The cache is in use, can't be cleared"
            } else {
                model.errorInfo = error.localizedDescription
            }
            
            model.showErrorToast = true
        }
    }

    func showCacheSize() {
        let wallpaperCacheSize = WallpaperManager.shared.cacheSize()
        let backNoisesCacheSize = BackNoisesTrackManager.shared.cacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        guard let byteCount = formatter.string(for: wallpaperCacheSize + backNoisesCacheSize) else { return }
        model.cacheSize = byteCount
    }

    func checkUpdate() {
        self.model.showProgress = true
        checkUpdatePresenter.checkUpdate(releaseType: GitHubRelease.self) { result in
            switch result {
            case .success:
                self.model.newestVersion = self.checkUpdatePresenter.latestVersion
                UserDefaults.standard.set(self.newestVersion,
                                          forKey: UserDefaults.Key.newestVersion)
                UserDefaults.standard.synchronize()
                if !self.checkUpdatePresenter.isTheNewestVersion {
                    Updater.checkForUpdates()
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
            self.model.showProgress = false
        }
    }
}
