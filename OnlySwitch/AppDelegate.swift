//
//  OnlySwitchApp.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI
import Cocoa

@main
struct OnlySwitchApp: App {
    let persistenceController = PersistenceController.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            SettingView()
        }
    }
}

@MainActor
class AppDelegate:NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var popover = NSPopover()
    let switchVM = SwitchVM()
    var blManager:BluetoothDevicesManager?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
            .environmentObject(switchVM)
        popover.contentSize = NSSize(width: popoverWidth, height: 300)
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
        CheckUpdateTool.shared.checkupdate(complete: { success in
            if success {
                let newestVersion = CheckUpdateTool.shared.latestVersion
                UserDefaults.standard.set(newestVersion, forKey: newestVersionKey)
                UserDefaults.standard.synchronize()
            }
        })
    }
    
}
