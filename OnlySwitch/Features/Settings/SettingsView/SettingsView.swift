//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import Aphrodite
import Authenticator
import Utilities
import OnlyAgent
import XcodeCleaner
import AppUninstaller
import Tailscale
import Extensions

struct SettingsView: View {
    @StateObject var settingVM = SettingsVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UserDefaults.Key.showXcodeCleanerTab) private var showXcodeCleanerTab = true
    @AppStorage(UserDefaults.Key.showAppUninstallerTab) private var showAppUninstallerTab = true

    init(settingItem: Binding<SettingsItem?> = .constant(nil)) {
        if let item = settingItem.wrappedValue {
            settingVM.selection = item
        }
    }

    func naviagtionView(currentLang: String) -> some View {
        NavigationView {
            List(selection: $settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        page(item: item)
                            .navigationTitle(item.titleLocalizationKey.localized())
                    } label:{
                        Text(item.titleLocalizationKey.localized())
                            .id(currentLang)
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Settings".localized())
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        settingVM.toggleSliderbar()
                    }, label: {
                        Image(systemName: "sidebar.leading")
                    })
                }
            }
    }

    @available(macOS 13.3, *)
    func naviagtionSplitView(currentLang: String) -> some View {
        NavigationSplitView(sidebar: {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink(value: item) {
                        Text(item.titleLocalizationKey.localized())
                            .id(currentLang)
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.sidebar)
        }, detail: {
            let selection = settingVM.selection ?? .General
            page(item: selection)
                .navigationTitle(selection.titleLocalizationKey.localized())
        })
    }

    @ViewBuilder
    func page(item: SettingsItem) -> some View {
        switch item {
            case .AirPods:
                AirPodsSettingView()

            case .Radio:
                RadioSettingView()

            case .Authenticator:
                AuthenticatorSettingsView()

            case .XcodeCleaner:
                ScrollView {
                    VStack(spacing: 0) {
                        Form {
                            Section {
                                Toggle("Xcode Cleaner Show Tab".localized(), isOn: $showXcodeCleanerTab)
                                    .onChange(of: showXcodeCleanerTab) { _ in
                                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                                    }
                            }
                        }
                        .formStyle(.grouped)
                        .contentMargins(.horizontal, 24, for: .scrollContent)
                        .tint(colorScheme == .dark ? .mint : .accentColor)
                        .scrollDisabled(true)
                        .frame(height: 76)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                        XcodeCleanerView(store: settingVM.xcodeCleanerStore, managesScrolling: false)
                            .id(langManager.currentLang)
                    }
                }
                .background(.background)

            case .AppUninstaller:
                ScrollView {
                    VStack(spacing: 0) {
                        Form {
                            Section {
                                Toggle("App Uninstaller Show Tab".localized(), isOn: $showAppUninstallerTab)
                                    .onChange(of: showAppUninstallerTab) { _ in
                                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                                    }
                            }
                        }
                        .formStyle(.grouped)
                        .contentMargins(.horizontal, 24, for: .scrollContent)
                        .tint(colorScheme == .dark ? .mint : .accentColor)
                        .scrollDisabled(true)
                        .frame(height: 76)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                        AppUninstallerView(store: settingVM.appUninstallerStore, managesScrolling: false)
                            .id(langManager.currentLang)
                    }
                }
                .background(.background)

            case .Tailscale:
                TailscaleSettingsView(store: settingVM.tailscaleStore)
                    .id(langManager.currentLang)
                    .onReceive(NotificationCenter.default.publisher(for: .changeSettings)) { _ in
                        settingVM.tailscaleStore.send(.refresh)
                    }
                    .onChange(of: settingVM.tailscaleStore.snapshot?.connection) { _, _ in
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                    }

            case .SystemMonitor:
                SystemMonitorSettingsView()

            case .PomodoroTimer:
                PomodoroTimerSettingView()

            case .Shortcuts:
                ShortcutsView()

            case .General:
                GeneralView()

            case .Customize:
                CustomizeView()

            case .HideMenubarIcons:
                HideMenubarIconsSettingView()

            case .BackNoises:
                BackNoisesSettingView()

            case .KeepAwake:
                KeepAwakeSettingView()

            case .DimScreen:
                DimScreenSettingView()

            case .Evolution:
                EvolutionView(store: settingVM.evolutionStore)

            case .ModelProviders:
                if #available(macOS 26.0, *) {
                    ModelProviderSettingView()
                } else {
                    EmptyView()
                }

            case .Aphrodite:
                if #available(macOS 26.0, *) {
                    AphroditeSettingsView(store: settingVM.aphroditeStore)
                } else {
                    AphroditeUnavailableView()
                }
            
            case .NightShift:
                NightShiftSettingsView()

            case .KeyLight:
                KeyLightView(store: settingVM.keyLightStore)

            case .PrivilegedAccess:
                PrivilegedAccessView()

            case .iOSRemote:
                RemoteAccessSettingsView(store: settingVM.remoteAccessStore)

            case .About:
                AboutView()
        }
    }

    var body: some View {
        if #available(macOS 13.3, *) {
            naviagtionSplitView(currentLang: langManager.currentLang)
        } else {
            naviagtionView(currentLang: langManager.currentLang)
        }
    }

}

#if DEBUG
struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
