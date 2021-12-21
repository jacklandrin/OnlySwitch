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
            EmptyView().frame(width: 10, height: 10)
        }
    }
}


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
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        
    }

    
}
