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
import OnlyControl
import Networking
import FirebaseCore
import Extensions
import DesktopPet
import UserNotifications
import OnlySwitchPersistence
import OSLog

struct OnlySwitchApp: App {
    let persistenceController = PersistenceController.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var preferencesvm = PreferencesObserver.shared
    @State var preferences = PreferencesObserver.shared.preferences
    @State var settingsItem: SettingsItem? = nil

    var body: some Scene {
        WindowGroup("run") {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    NSApp.hideDockIcon()
                }
                .onDisappear() {
                    NSApp.hideDockIcon()
                }
                .onOpenURL{ url in
                    defer {
                        if let window = NSApplication.shared.windows.first(where: { $0.title == "run"}) {
                            window.close()
                            NSApp.hideDockIcon()
                        }
                    }
                    guard url.absoluteString.contains("run"),
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let queryItems = components.queryItems,
                          let typeStr = queryItems.first(where: {$0.name == "type"})?.value,
                          let unitType =  UnitType(rawValue: typeStr),
                          let id = queryItems.first(where: {$0.name == "id"})?.value
                    else {
                        return
                    }

                    if unitType == .builtIn {
                        guard
                            let intID = UInt64(id),
                            let type = SwitchType(legacyIdentifier: intID)
                        else {
                            return
                        }
                        let theSwitch = CustomizeVM.shared.allSwitches.first{ $0.type == type }
                        Task {
                            await theSwitch?.doSwitch()
                        }
                    } else if unitType == .evolution {
                        guard
                            let uuid = UUID(uuidString: id),
                            let entity = try? EvolutionCommandEntity.fetchRequest(by: uuid)
                        else {
                            return
                        }
                        let item = EvolutionAdapter.toEvolutionItem(entity)
                        item?.doSwitch()
                    }
                }
        }
        .windowKeepContentSize()
        .handlesExternalEvents(matching: Set(arrayLiteral: "run"))

        WindowGroup("Settings".localized()) {
            settings
        }
        .windowResizability(.contentMinSize)
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

    private var settings: some View {
        SettingsView(settingItem: $settingsItem)
            .frame(minWidth: Layout.settingWindowWidth, minHeight: Layout.settingWindowHeight)
            .onDisappear {
                if #available(macOS 13.3, *) {
                    Logger.app.debug("settings window closing")
                    NSApp.activate(ignoringOtherApps: false)
                    NSApp.setActivationPolicy(.accessory)
                    NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
                }
            }
            .onOpenURL{ url in
                guard url.absoluteString.contains("destination"),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems,
                      let destination = queryItems.first(where: { $0.name == "destination" })?.value
                else {
                    return
                }
                let itemString = destination.replacingOccurrences(of: "_", with: " ").capitalized
                if let item = SettingsItem(rawValue: itemString) {
                    settingsItem = item
                }
            }

    }
}

extension NSApplication {
    func hideDockIcon() {
        if !SettingsWindow.shared.isShowing {
            setActivationPolicy(.accessory)
        }
    }
}
