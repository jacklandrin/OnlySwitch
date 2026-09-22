//
//  GeneralVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/5.
//

import AppKit
import Combine
import Extensions
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

    var showDesktopPet: Bool {
        get {
            preferences.showDesktopPet
        }
        set {
            preferences.showDesktopPet = newValue
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
    
    var showSuccessToast: Bool {
        get {
            model.showSuccessToast
        }
        set {
            model.showSuccessToast = newValue
        }
    }

    var successInfo: String {
        model.successInfo
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

extension GeneralVM {
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "\(Bundle.appIdentifier)OnlySwitch.shared")
    }

    func exportSettings() {
        do {
            let backup = SettingsBackup(
                preferences: SettingsBackup.collectPreferences(from: .standard),
                sharedPreferences: Self.sharedDefaults.map(SettingsBackup.collectSharedPreferences(from:)) ?? [:],
                radioStations: RadioStations.backupEntries(),
                evolution: EvolutionBackup(
                    preExecution: UserDefaults.standard.string(forKey: EvolutionBackup.preExecutionKey),
                    commands: try EvolutionCommandEntity.backupCommands()
                )
            )
            let data = try backup.encoded()
            let savePanel = buildBackupSavePanel()
            savePanel.begin { result in
                guard result == .OK, let url = savePanel.url else { return }
                do {
                    try data.write(to: url)
                    self.model.successInfo = "Settings exported successfully".localized()
                    self.model.showSuccessToast = true
                } catch {
                    self.model.errorInfo = error.localizedDescription
                    self.model.showErrorToast = true
                }
            }
        } catch {
            self.model.errorInfo = error.localizedDescription
            self.model.showErrorToast = true
        }
    }

    func importSettings() {
        let openPanel = buildBackupOpenPanel()
        openPanel.begin { result in
            guard result == .OK, let url = openPanel.url else { return }
            do {
                let backup = try SettingsBackup(data: Data(contentsOf: url))
                let includeEvolution = !backup.evolution.isEmpty && self.confirmEvolutionImport(backup.evolution)
                try self.restore(backup, includeEvolution: includeEvolution)
                self.model.successInfo = "Settings imported. Restart Only Switch to apply all changes".localized()
                self.model.showSuccessToast = true
            } catch {
                self.model.errorInfo = error.localizedDescription
                self.model.showErrorToast = true
            }
        }
    }

    private func restore(_ backup: SettingsBackup, includeEvolution: Bool) throws {
        SettingsBackup.replace(backup.preferences, in: .standard, isAllowed: SettingsBackup.isExportablePreference)
        if let sharedDefaults = Self.sharedDefaults {
            SettingsBackup.replace(backup.sharedPreferences, in: sharedDefaults, isAllowed: SettingsBackup.isSharedPreference)
        }
        try RadioStations.restore(backup.radioStations)
        if includeEvolution {
            try EvolutionCommandEntity.restore(backup.evolution.commands)
            if let preExecution = backup.evolution.preExecution {
                UserDefaults.standard.set(preExecution, forKey: EvolutionBackup.preExecutionKey)
            }
        }
    }

    /// Evolution items are shell commands (status checks run automatically), so a backup from
    /// someone else must never install them without the user seeing what they are.
    private func confirmEvolutionImport(_ evolution: EvolutionBackup) -> Bool {
        var details = evolution.commands.compactMap { $0["name"] }.map { "• \($0)" }
        if let preExecution = evolution.preExecution, !preExecution.isEmpty {
            details.append("\("Pre-execution:".localized()) \(preExecution)")
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Import custom Evolution commands?".localized()
        alert.informativeText = "This backup contains shell commands that Only Switch will run on this Mac, some of them automatically. Only import them if you trust whoever created this file.".localized()
            + "\n\n" + details.joined(separator: "\n")
        alert.addButton(withTitle: "Skip Commands".localized())
        alert.addButton(withTitle: "Import Commands".localized())
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func buildBackupSavePanel() -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Settings".localized()
        savePanel.nameFieldStringValue = "OnlySwitch_settings"
        savePanel.allowedContentTypes = [.propertyList]
        return savePanel
    }

    private func buildBackupOpenPanel() -> NSOpenPanel {
        let openPanel = NSOpenPanel()
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.propertyList]
        return openPanel
    }
}
