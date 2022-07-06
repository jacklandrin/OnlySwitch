//
//  OnlySwitchApp.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI
import Cocoa
import KeyboardShortcuts

@main
struct OnlySwitchApp: App {
    let persistenceController = PersistenceController.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("SettingsWindow"){
            SettingView()
                .frame(width: Layout.settingWindowWidth, height: Layout.settingWindowHeight)
                .task {
                    CustomizeVM.shared.allSwitches.forEach{ item in
                        KeyboardShortcuts.onKeyDown(for: item.keyboardShortcutName) {
                            item.doSwitch()
                        }
                    }
                    
                    ShortcutsSettingVM.shared.shortcutsList.forEach{ item in
                        KeyboardShortcuts.onKeyDown(for: item.keyboardShortcutName) {
                            item.doShortcuts()
                        }
                    }
                }
        }.handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        Settings{
            SettingView()
        }
    }
}

class AppDelegate:NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var popover = NSPopover()
    let switchVM = SwitchListVM()
    var blManager:BluetoothDevicesManager?
    var currentAppearance:String {
        return Preferences.shared.currentAppearance
    }
    var checkUpdatePresenter = GitHubPresenter()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = OnlySwitchListView()
            .environmentObject(switchVM)
        let apperearance = SwitchListAppearance(rawValue: currentAppearance)
        
        popover.contentSize = NSSize(width: apperearance == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40, height: 300)
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        statusBar = StatusBarController(popover)
        
        SwitchManager.shared.registerSwitchesShouldShow()
        
        blManager = BluetoothDevicesManager.shared
        RadioStationSwitch.shared.setDefaultRadioStations()
        Bundle.setLanguage(lang: LanguageManager.sharedManager.currentLang)
        
        checkUpdate()
        //for issue #11
        if let window = NSApplication.shared.windows.first {
            window.close()
        }
       
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        
    }
    
    func checkUpdate() {
        checkUpdatePresenter.checkUpdate { result in
            switch result {
            case .success:
                let newestVersion = self.checkUpdatePresenter.latestVersion
                UserDefaults.standard.set(newestVersion, forKey: UserDefaults.Key.newestVersion)
                UserDefaults.standard.synchronize()
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
}
