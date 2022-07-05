//
//  GeneralVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/5.
//

import AppKit

class GeneralVM:ObservableObject {
    
    @Published private var model = GeneralModel()
    @Published private var preferences = Preferences.shared
    
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
    
    var showProgress:Bool {
        return model.showProgress
    }
    
    var newestVersion:String {
        return model.newestVersion
    }
    
    var supportedLanguages:[Language] {
        return model.supportedLanguages
    }
    
    var showMenubarIconPopover:Bool {
        get {
            return model.showMenubarIconPopover
        }
        set {
            model.showMenubarIconPopover = newValue
        }
    }
    
    var menubarIcons:[String] {
        return model.menubarIcons
    }
    
    private let checkUpdatePresenter = GitHubPresenter()
    
    var currentMenubarIcon:String
    {
        get {
            preferences.currentMenubarIcon
        }
        set {
            preferences.currentMenubarIcon = newValue
        }
    }
    
    var currentAppearance:String {
        get {
            preferences.currentAppearance
        }
        set {
            preferences.currentAppearance = newValue
        }
    }
    
    var showAds:Bool {
        get {
            preferences.showAds
        }
        set {
            preferences.showAds = newValue
        }
    }
    
    var latestVersion:String {
        return checkUpdatePresenter.latestVersion
    }
    
    var isTheNewestVersion:Bool {
        return checkUpdatePresenter.isTheNewestVersion
    }
    
    func checkUpdate() {
        self.model.showProgress = true
        checkUpdatePresenter.checkUpdate(complete: { result in
            switch result {
            case .success:
                self.model.newestVersion = self.checkUpdatePresenter.latestVersion
                UserDefaults.standard.set(self.newestVersion, forKey: UserDefaults.Key.newestVersion)
                UserDefaults.standard.synchronize()
                self.model.needtoUpdateAlert = !self.checkUpdatePresenter.isTheNewestVersion
            case let .failure(error):
                print(error.localizedDescription)
            }
            self.model.showProgress = false
        })
    }
    
    
    func downloadDMG() {
        checkUpdatePresenter.downloadDMG{ result in
            switch result {
            case let .success(path):
                self.openDMG(path: path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    NSApp.terminate(self)
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
    private func openDMG(path:String) {
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: finder!, configuration: configuration, completionHandler: nil)
    }
}



