//
//  OnlySwitchApp.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI
import Cocoa
import KeyboardShortcuts
import Defines
import Switches
import Utilities

@main
struct OnlySwitchApp: App {
    let persistenceController = PersistenceController.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var preferencesvm = PreferencesObserver.shared
    @State var preferences = PreferencesObserver.shared.preferences
    
    var body: some Scene {
        WindowGroup("performswitch") {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    if appDelegate.switchVM.isSettingViewShowing == true {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
                .onOpenURL{ url in
                    guard url.absoluteString.contains("performswitch"),
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let queryItems = components.queryItems,
                          let typeStr = queryItems.first(where: {$0.name == "type"})?.value,
                          let unitType =  UnitType(rawValue: typeStr),
                          let id = queryItems.first(where: {$0.name == "id"})?.value
                    else {
                        return
                    }

                    if unitType == .buildIn {
                        guard 
                            let intID = UInt64(id),
                            let type = SwitchType(rawValue: intID)
                        else {
                            return
                        }
                        let theSwitch = CustomizeVM.shared.allSwitches.first{ $0.type == type }
                        theSwitch?.doSwitch()
                    }

                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowKeepContentSize()
        .handlesExternalEvents(matching: Set(arrayLiteral: "performswitch"))

        WindowGroup("SettingsWindow") {
            SettingsView()
                .frame(width: Layout.settingWindowWidth, height: Layout.settingWindowHeight)
                .onDisappear {
                    if #available(macOS 13.3, *) {
                        print("settings window closing")
                        NSApp.activate(ignoringOtherApps: false)
                        NSApp.setActivationPolicy(.accessory)
                        NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
                        appDelegate.switchVM.isSettingViewShowing = false
                    }
                }
        }
        .windowKeepContentSize()
        .handlesExternalEvents(matching: Set(arrayLiteral: "SettingsWindow"))
        .commands{
            CommandMenu("Switches Availability") {
                Button(action: {
                    preferencesvm.preferences.radioEnable = !preferences.radioEnable
                    if preferences.radioEnable {
                        PlayerManager.shared.player.setupRemoteCommandCenter()
                    } else {
                        RadioStationSwitch.shared.playerItem.isPlaying = false
                        PlayerManager.shared.player.clearCommandCenter()
                    }
                }, label: {
                    if preferencesvm.preferences.radioEnable {
                        Text("Disable Player")
                    } else {
                        Text("Enable Player")
                    }
                })
                Button(action: {
                    preferencesvm.preferences.menubarCollaspable = !preferences.menubarCollaspable
                }, label: {
                    if preferencesvm.preferences.menubarCollaspable {
                        Text("Disable Hide Menu Bar Icons")
                    } else {
                        Text("Enable Hide Menu Bar Icons")
                    }
                })
            }
            SidebarCommands()
            CommandGroup(after: .appSettings) {
                Button(action: {
                    appDelegate.checkUpdate()
                }, label: {
                    Text("Check For Update...")
                })
            }
            CommandGroup(replacing: .newItem) {
                
            }
        }
    }
}

class AppDelegate:NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var popover = NSPopover()
    let switchVM = SwitchListVM()
    var blManager:BluetoothDevicesManager?
    var currentAppearance:String {
        return PreferencesObserver
            .shared
            .preferences
            .currentAppearance
    }
    var checkUpdatePresenter = GitHubPresenter.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        //for issue #11
        if let window = NSApplication.shared.windows.first {
            window.orderOut(nil)
            NSApplication.shared.setActivationPolicy(.accessory)
            NSWindow.allowsAutomaticWindowTabbing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                window.close()
            }
        }
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

        registerShortcut()
        checkUpdate()
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
                if !self.checkUpdatePresenter.isTheNewestVersion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        Updater.checkForUpdates()
                    }
                }

            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func registerShortcut() {
        KeyboardShortcuts.onKeyDown(for: .invokePopoverShortcutsName) {
            NotificationCenter.default.post(name: .togglePopover, object: nil)
        }

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

        if let entities = try? EvolutionCommandEntity.fetchResult() {
            let evolutionItems = EvolutionAdapter.evolutionItems(entities)
            evolutionItems.forEach{ item in
                KeyboardShortcuts.onKeyDown(for: KeyboardShortcuts.Name(rawValue: item.id.uuidString)!) {
                    item.doSwitch()
                }
            }
        }
    }
}
