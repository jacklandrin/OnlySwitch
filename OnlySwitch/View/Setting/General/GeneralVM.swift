//
//  GeneralVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/5.
//

import AppKit

let menubarIconKey = "menubarIconKey"
let appearanceColumnCountKey = "appearanceColumnCountKey"
let showAdsKey = "showAdsKey"

class GeneralVM:ObservableObject {
    
    @Published private var model = GeneralModel()
    
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
    
    @UserDefaultValue(key: menubarIconKey, defaultValue: "menubar_0")
    var currentMenubarIcon:String
    {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: changeMenuBarIconNotificationName, object: currentMenubarIcon)
        }
    }
    
    @UserDefaultValue(key: appearanceColumnCountKey, defaultValue: SwitchListAppearance.single.rawValue)
    var currentAppearance:String {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: changePopoverAppearanceNotificationName, object: nil)
        }
    }
    
    @UserDefaultValue(key: showAdsKey, defaultValue: true)
    var showAds:Bool {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: changeSettingNotification, object: nil)
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
        checkUpdatePresenter.checkUpdate(complete: { success in
            if success {
                self.model.newestVersion = self.checkUpdatePresenter.latestVersion
                UserDefaults.standard.set(self.newestVersion, forKey: newestVersionKey)
                UserDefaults.standard.synchronize()
                self.model.needtoUpdateAlert = !self.checkUpdatePresenter.isTheNewestVersion
            }
            self.model.showProgress = false
        })
    }
    
    
    func downloadDMG() {
        checkUpdatePresenter.downloadDMG{ success, path in
            guard success, let path = path else {return}
            self.openDMG(path: path)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.terminate(self)
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

enum SwitchListAppearance:String {
    case single = "Single Column"
    case dual = "Two Columns"
}

